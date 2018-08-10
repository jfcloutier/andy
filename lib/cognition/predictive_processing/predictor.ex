defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ PubSub, Prediction, GenerativeModels, Belief, Fulfillment, GenerativeModels }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_pid, model_name]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_pid, model_name] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(prediction, believer_pid, model_name) do
    predictor_name = "#{prediction.name}(#{model_name})"
    { :ok, pid } = Agent.start_link(
      fn ->
        register_internal()
        %{
          predictor_name: predictor_name,
          predicted_model_name: model_name,
          # believer making (owning) the prediction
          believer: believer_pid,
          # the prediction made
          prediction: prediction,
          # the effective precision for the prediction
          effective_precision: prediction.precision,
          # Is is currently fulfilled? For starters, yes
          fullfilled?: true,
          # index of the fulfillment being tried. Nil if none.
          fulfillment_index: nil
        }
      end,
      [name: predictor_name]
    )
    Task.async(fn -> predict(pid) end)
    Logger.info("#{__MODULE__} started on prediction #{Prediction.summary(prediction)}")
    { :ok, pid }
  end

  def predict(predictor_pid) do
    grab_believer(predictor_pid)
    direct_attention(predictor_pid)
  end

  def about_to_be_terminated(predictor_pid) do
    PubSub.notify_attention_off(predictor_pid)
  end

  defp fulfillment_data(predictor_name) do
    Agent.get(
      predictor_name,
      fn (state) ->
        { state.fulfillment_index, Enum.count(state.prediction.fulfillments) }
      end
    )
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  def handle_event({ :perceived, %Percept{ } = percept }, %{ prediction: prediction } = state) do
    # Validate perceived if relevant
    if percept_relevant?(percept, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        { :believed, %Belief{ } = belief },
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
        { :fulfill, %Fulfill{ predictor_name, new_fulfillment_index } },
        %{ fulfillment_index: current_fulfillment_index } = state
      ) do
    # Try a given fulfillment in response to a prediction error -
    # It might instantiate a temporary model believer for a fulfillment action
    if new_fulfillment_index != current_fulfillment_index do
      updated_state = deactivate_current_fulfillment(state)
      activate_fulfillment(fulfillment_index, updated_state, :first_time)
    else
      activate_fulfillment(fulfillment_index, state, :repeated)
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

  defp grab_believer(predictor_pid) do
    Agent.update(
      predictor_pid,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { _is_or_not, model_name } ->
            believer_id = BelieversSupervisor.grab_believer(model_name, predictor_pid)
            %{ state | believer: believer_id }
        end
      end
    )
  end

  defp direct_attention(predictor_pid) do
    { detector_specs, precision } = required_detection(predictor_pid)
    PubSub.notify_attention_on(detector_specs, predictor_pid, precision)
  end

  defp required_detection(predictor_pid) do
    Agent.get(
      predictor_pid,
      fn (%{ prediction: prediction, effective_precision: effective_precision }) ->
        { Prediction.detector_specs(prediction), effective_precision }
      end
    )
  end

  defp percept_relevant?(
         %Percept{ about: percept_about },
         %{ perceived: perceived_specs } = _prediction
       ) do
    Enum.any?(
      perceived_specs,
      fn (perceived_spec) ->
        Percept.about_match?(perceived_spec, percept_about)
      end
    )
  end

  defp belief_relevant?(
         %Belief{ model_name: model_name },
         %{ believed: { _is_or_not, believed_model_name } = _prediction }
       ) do
    model_name == believed_model_name
  end

  defp review_prediction(
         %{
           prediction: prediction,
           fulfilled?: fulfilled?,
           effective_precision: precision
         } = state
       ) do
    if prediction_fulfilled?(prediction, precision) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true
      if not fulfilled? do
        PubSub.notify_fulfilled(
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
    believed_as_predicted?(prediction, precision)
    and perceived_as_predicted?(prediction, precision)
  end

  defp believed_as_predicted?(
         %{ believed: nil } = _prediction,
         _precision
       ) do
    true
  end

  defp believed_as_predicted?(
         %{ believed: { is_or_not, model_name } } = _prediction,
         precision
       ) do
    believer = BelieversSupervisor.find_believer(model_name)
    believes? = Believer.believes?(believer, precision)
    case is_nor_not do
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
    Enum.count(fitting_percepts) / Enum.count(percepts)
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
    average = Enum.reduce(before, 0, &(&1.value + acc))
    percept.value >= average
  end

  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:descending, percept, percepts) do
    { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
    average = Enum.reduce(before, 0, &(&1.value + acc))
    percept.value <= average
  end

  defp prediction_error(state) do
    Prediction.new(
      predictor_name: state.predictor_name,
      model_name: state.model_name,
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

  defp deactivate_fulfillment(
         %{
           fulfillment_index: fulfillment_index,
           prediction: prediction,
           predictor_name: predictor_name
         } = state
       ) do
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index)
    # Stop whatever was started when activating the current fulfillment, if any
    if  fulfillment.model_name != nil do
      BelieversSupervisor.release_believer(fulfillment.model_name, predictor_name)
    end
    %{ state | fulfillment_index: nil }
  end

  defp activate_fulfillment(
         fulfillment_index,
         state,
         first_time_or_repeated
       ) do
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index)
    if  fulfillment.model_name != nil and first_time_or_repeated == :first_time do
      BelieversSupervisor.grab_believer(fulfillment.model_name, state.predictor_name)
    end
    if fulfillment.actions != nil do
      Enum.each(fulfillment.actions, Action.execute(&1))
    end
    %{ state | fulfillment_index: fulfillment_index }
  end

  defp reduce_precision_by(precision, priority) do
    case priority do
      :none ->
        precision
      other ->
        Andy.reduce_level_by(precision, priority)
    end
  end

end