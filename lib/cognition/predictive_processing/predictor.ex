defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ PubSub, Prediction, GenerativeModels, Belief, Fulfillment, GenerativeModels }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_pid]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_pid] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(prediction, believer_pid) do
    { :ok, pid } = Agent.start_link(
      fn ->
        register_internal()
        %{
          # believer making the prediction
          believer: believer_pid,
          # the prediction made
          prediction: prediction,
          # the effective precision for the prediction
          effective_precision: prediction.precision,
          # Is is currently fulfilled? For starters, yes
          fullfilled?: true
        }
      end,
      [name: generative_model.name]
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
    Attention.lose_attention(predictor_pid)
  end

  defp grab_believer(predictor_pid) do
    Agent.update(
      predictor_pid,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { _is_or_not, model_name } ->
            model = GenerativeModels.named(model_name)
            believer_id = BelieversSupervisor.grab_believer(model, predictor_pid)
            %{ state | believer: believer_id }
        end
      end
    )
  end

  defp direct_attention(predictor_pid) do
    detector_specs = detector_specs(predictor_pid)
    Attention.pay_attention(detector_specs, predictor_pid)
  end

  defp detector_specs(predictor_pid) do
    Agent.get(
      predictor_pid,
      fn (%{ prediction: prediction }) ->
        Prediction.detector_specs(prediction)
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

  def handle_event({ :believed, %Belief{ } = belief }, %{ prediction: prediction } = state) do
    # Validate believed if relevant
    if belief_relevant?(belief, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event({ :fulfill, %Fulfill{ } }, state) do
    # Try a fulfillment in response to a prediction error -
    # It might instantiate a temporary model believer for a fulfillment action
    #
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  #### Private

  defp percept_relevant?(
         %Percept{ about: percept_about },
         %{ perceived: perceived_specs } = _prediction
       ) do
    Enum.any?(
      perceived_specs,
      fn (perceived_spec) ->
        match?(perceived_spec, percept_about)
      end
    )
  end

  defp belief_relevant?(
         %Belief{ model_name: model_name },
         %{ believed: { _is_or_not, believed_model_name } = _prediction }
       ) do
    model_name == believed_model_name
  end

  defp match?(perceived_spec, percept_about) do
    # Both have the same keys
    keys = Map.keys(perceived_spec)
    Enum.all?(
      keys,
      fn (key) -> perceived.val = Map.fetch!(perceived_spec, key)
                  percept.val = Map.fetch!(percept_about, key)
                  perceived.val == "*"
                  or percept_val == "*"
                  or perceived_val == percept_val
      end
    )
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
      # Notify of prediction recovered if prediction becomes true enough
      if not fulfilled? do
        PubSub.notify_fulfilled(
          PredictionFulfilled.new(
            model_name: state.model_name,
            prediction: state.prediction
          )
        )
      end
      fulfilled_state
    else
      unfulfilled_state = %{ state | fulfilled?: false }
      # Notify of prediction error if prediction not true enough
      prediction_error = prediction_error(state)
      PubSub.notify_prediction_error(prediction_error)
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

  defp probability_of_perceived({percept_about, predicate, time_period} = _perceived) do
    percepts = Memory.recall_percepts(percept_about, time_period)
    fitting_percepts = Enum.filter(percepts, &(apply_predicate(predicate, &1)))
    Enum.count(fitting_percepts) / Enum.count(percepts)
  end

  defp apply_predicate(predicate, percept) do
    # TODO
    true
  end

  defp prediction_error(state) do
    #TODO
  end

end