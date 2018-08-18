defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ PubSub, Prediction, Percept, Belief, Fulfill, Action,
               Believer, BelieversSupervisor, Memory, PredictionFulfilled, PredictionError }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_name, model_name]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_name, model_name] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(prediction, believer_name, model_name) do
    predictor_name = String.to_atom("#{prediction.name} in #{model_name}")
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          predictor_name: predictor_name,
          predicted_model_name: model_name,
          # believer making (owning) the prediction
          believer_name: believer_name,
          # the prediction made
          prediction: prediction,
          # the effective precision for the prediction
          effective_precision: prediction.precision,
          # Is is currently fulfilled? For starters, yes
          fulfilled?: true,
          # index of the fulfillment being tried. Nil if none.
          fulfillment_index: nil
        }
      end,
      [name: predictor_name]
    )
    spawn(fn -> predict(predictor_name) end)
    Logger.info("#{__MODULE__} started on #{Prediction.summary(prediction)}")
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  def predict(predictor_name) do
    grab_believer(predictor_name)
    direct_attention(predictor_name)
  end

  def about_to_be_terminated(predictor_name) do
    PubSub.notify_attention_off(predictor_name)
    release_believer(predictor_name)
    deactivate_predictor_fulfillment(predictor_name)
  end

  def fulfillment_data(predictor_name) do
    Agent.get(
      predictor_name,
      fn (state) ->
        { state.fulfillment_index, Enum.count(state.prediction.fulfillments) }
      end
    )
  end

  ### Cognition Agent Behaviour

  def handle_event(
        { :percept_memorized, %Percept{ } = percept },
        %{ prediction: prediction } = state
      ) do
    # Validate perceived if relevant
    if percept_relevant?(percept, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        { :belief_memorized, %Belief{ } = belief },
        %{
          prediction: prediction
        } = state
      ) do
    # Validate believed if relevant
    if belief_relevant?(belief, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        {
          :fulfill,
          %Fulfill{
            predictor_name: fulfill_predictor_name,
            fulfillment_index: new_fulfillment_index
          }
        },
        %{
          predictor_name: predictor_name,
          fulfillment_index: current_fulfillment_index
        } = state
      ) do
    # Try a given fulfillment in response to a prediction error -
    # It might instantiate a temporary model believer for a fulfillment action
    if predictor_name == fulfill_predictor_name do
      if new_fulfillment_index != current_fulfillment_index do
        updated_state = deactivate_fulfillment(state)
        activate_fulfillment(new_fulfillment_index, updated_state, :first_time)
      else
        activate_fulfillment(new_fulfillment_index, state, :repeated)
      end
    else
      state
    end
  end

  def handle_event(
        { :model_deprioritized, model_name, priority },
        %{
          predicted_model_name: predicted_model_name,
          precision: precision
        } = state
      ) do
    if model_name == predicted_model_name do
      updated_effective_precision = reduce_precision_by(precision, priority)
      %{ state | effective_precision: updated_effective_precision }
    else
      state
    end
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  #### Private

  defp grab_believer(predictor_name) do
    Agent.update(
      predictor_name,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { _is_or_not, model_name } ->
            believer_name = BelieversSupervisor.grab_believer(model_name, predictor_name)
            %{ state | believer_name: believer_name }
        end
      end
    )
  end

  defp release_believer(predictor_name) do
    Agent.update(
      predictor_name,
      fn (%{ believer_name: believer_name } = state) ->
        if believer_name != nil do
          BelieversSupervisor.release_believer_named(believer_name, predictor_name)
          %{ state | believer_name: nil }
        end
      end
    )
  end

  defp direct_attention(predictor_name) do
    { detector_specs_list, precision } = required_detection(predictor_name)
    detector_specs_list
    |> Enum.each(&(PubSub.notify_attention_on(&1, predictor_name, precision)))
  end

  defp required_detection(predictor_name) do
    Agent.get(
      predictor_name,
      fn (%{ prediction: prediction, effective_precision: effective_precision }) ->
        { Prediction.detector_specs(prediction), effective_precision }
      end
    )
  end

  defp percept_relevant?(
         %Percept{ about: percept_about },
         %Prediction{ perceived: perceived_specs } = _prediction
       ) do
    Enum.any?(
      perceived_specs,
      fn ({ perceived_about, _predicate, _time } = _perceived_spec) ->
        Percept.about_match?(perceived_about, percept_about)
      end
    )
  end

  defp belief_relevant?(
         _belief,
         %Prediction{ believed: nil } = _prediction
       ) do
    false
  end

  defp belief_relevant?(
         %Belief{ model_name: model_name },
         %Prediction{ believed: { _is_or_not, believed_model_name } = _prediction }
       ) do
    model_name == believed_model_name
  end

  defp review_prediction(
         %{
           prediction: prediction,
           fulfilled?: was_fulfilled?,
           effective_precision: precision
         } = state
       ) do
    if prediction_fulfilled?(prediction, precision) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true
      if not was_fulfilled? do
        PubSub.notify_prediction_fulfilled(
          prediction_fulfilled(state)
        )
        deactivate_fulfillment(state)
      end
      fulfilled_state
    else
      unfulfilled_state = %{ state | fulfilled?: false }
      # Notify of prediction error if prediction (still) not true
      PubSub.notify_prediction_error(prediction_error(state))
      unfulfilled_state
    end
  end

  defp prediction_fulfilled?(prediction, precision) do
    believed_as_predicted?(prediction)
    and perceived_as_predicted?(prediction, precision)
  end

  defp believed_as_predicted?(
         %{ believed: nil } = _prediction
       ) do
    true
  end

  defp believed_as_predicted?(
         %{ believed: { is_or_not, model_name } } = _prediction
       ) do
    believer_name = BelieversSupervisor.find_believer_name(model_name)
    believes? = Believer.believes?(believer_name)
    case is_or_not do
      :is -> believes?
      :not -> not believes?
    end
  end

  defp perceived_as_predicted?(%{ perceived: [] } = _prediction, _precision) do
    true
  end

  defp perceived_as_predicted?(%{ perceived: perceived_list } = _prediction, precision) do
    probability = Enum.reduce(
      perceived_list,
      1.0,
      fn (perceived, acc) ->
        probability_of_perceived(perceived) * acc
      end
    )
    Andy.in_probable_range?(probability, precision)
  end


  defp probability_of_perceived({ percept_about, predicate, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    fitting_percepts = Enum.filter(percepts, &(apply_predicate(predicate, &1, percepts)))
    percepts_count = Enum.count(percepts)
    if percepts_count == 0, do: 0, else: Enum.count(fitting_percepts) / percepts_count
  end

  defp apply_predicate({ :gt, val }, percept, _percepts) do
    percept.value > val
  end

  defp apply_predicate({ :lt, val }, percept, _percepts) do
    percept.value < val
  end

  defp apply_predicate({ :eq, val }, percept, _percepts) do
    percept.value == val
  end

  defp apply_predicate({ :neq, val }, percept, _percepts) do
    percept.value != val
  end

  defp apply_predicate({ :in, range }, percept, _percepts) do
    percept.value in range
  end

  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:ascending, percept, percepts) do
    { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
    average = Enum.reduce(before, 0, &(&1.value + &2))
    percept.value >= average
  end

  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:descending, percept, percepts) do
    { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
    average = Enum.reduce(before, 0, &(&1.value + &2))
    percept.value <= average
  end

  defp prediction_error(state) do
    PredictionError.new(
      predictor_name: state.predictor_name,
      model_name: state.predicted_model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index
    )
  end

  defp prediction_fulfilled(state) do
    PredictionFulfilled.new(
      predictor_name: state.predictor_name,
      model_name: state.model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index
    )
  end

  defp deactivate_predictor_fulfillment(predictor_name) do
    Agent.update(
      predictor_name,
      fn (state) ->
        deactivate_fulfillment(state)
      end
    )
  end

  defp deactivate_fulfillment(
         %{
           fulfillment_index: nil
         } = state
       ) do
    state
  end

  defp deactivate_fulfillment(
         %{
           fulfillment_index: fulfillment_index,
           prediction: prediction,
           predictor_name: predictor_name
         } = state
       ) do
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index - 1)
    # Stop whatever was started when activating the current fulfillment, if any
    if  fulfillment.model_name != nil do
      BelieversSupervisor.release_believer(fulfillment.model_name, predictor_name)
    end
    %{ state | fulfillment_index: nil }
  end

  defp activate_fulfillment(
         0,
         state,
         _first_time_or_repeated
       ) do
    Logger.info("Activating no fulfillment in predictor #{state.predictor_name}")
    %{ state | fulfillment_index: nil }
  end

  defp activate_fulfillment(
         fulfillment_index,
         %{
           prediction: prediction,
           predictor_name: predictor_name
         } = state,
         first_time_or_repeated
       ) do
    Logger.info("Activating fulfillment #{fulfillment_index} in predictor #{predictor_name}")
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index - 1)
    if  fulfillment.model_name != nil do
      BelieversSupervisor.grab_believer(fulfillment.model_name, predictor_name)
    end
    if fulfillment.actions != nil do
      Enum.each(fulfillment.actions, &(Action.execute(&1, first_time_or_repeated)))
    end
    %{ state | fulfillment_index: fulfillment_index }
  end

  defp reduce_precision_by(precision, priority) do
    case priority do
      :none ->
        precision
      _other ->
        Andy.reduce_level_by(precision, priority)
    end
  end

end