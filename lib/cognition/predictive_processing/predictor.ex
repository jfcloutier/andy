defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ InternalCommunicator, Prediction, GenerativeModels, Belief, Fulfillment }

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
          model_name: generative_model.name,
          believer: believer_pid,
          prediction: prediction,
          effective_precision: prediction.precision,
          # For starters
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
            if model == nil, do: raise "Model #{model_name} does not exist"
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
    InternalCommunicator.register(__MODULE__)
  end

  def handle_event({ :perceived, %Percept{ } = percept }, %{ prediction: prediction } = state) do
    # Validate perceived if relevant
    if percept_relevant?(percept, prediction) do
      review_fulfilled(state)
    else
      state
    end
  end

  def handle_event({ :believed, %Belief{ } = belief }, %{ prediction: prediction } = state) do
    # Validate believed if relevant
    if belief_relevant?(belief, prediction) do
      review_fulfilled(state)
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
         %{ believed: { _is_or_not, believed_model_name } }
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

  defp review_fulfilled(%{ fulfilled?: fulfilled? } = state) do
    if fulfilled?(prediction) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true enough
      if not fulfilled? do
        InternalCommunicator.notify_fulfilled(
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
      InternalCommunicator.notify_prediction_error(prediction_error)
      unfulfilled_state
    end
  end

  defp fulfilled?(prediction) do
    # TODO
    true
  end
  
  defp prediction_error(state) do
    #TODO
  end

end