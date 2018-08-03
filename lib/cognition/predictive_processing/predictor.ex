defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ InternalCommunicator, Prediction, GenerativeModels, Belief, Fulfillment }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(prediction, believer_pid) do
    { :ok, pid } = Agent.start_link(
      fn ->
        register_internal()
        %{
          believer: believer_pid,
          prediction: prediction,
          effective_precision: prediction.precision,
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
    detector_specs = detector_specs(predictor_pid)
    Attention.lose_attention(predictor_pid)
  end

  defp grab_believer(predictor_pid) do
    Agent.update(
      predictor_pid,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { _, model_name } ->
            model = GenerativeModels.named(model_name)
            if model == nil, do: raise "Model #{model_name} does not exist"
            believer_id = BelieversSupervisor.grab_believer(model)
            %{ state | believer: believer_id }
        end
      end
    )
  end

  defp pay_attention(predictor_pid) do
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

  # TBD
  # Listens to relevant predicted percepts or changed beliefs
  # If prediction false enough given effective precision:
  #   Raise prediction error
  #
  #
  def handle_event(%Percept{ } = percept, state) do
    # Validate perceived if relevant
    # Notify of prediction error if prediction not true enough
    # Notify of prediction recovered if prediction becomes true enough
    state
  end

  def handle_event(%Belief{ } = belief, state) do
    # Validate believed if relevant
    # Notify of prediction error if prediction not true enough
    state
  end

  def handle_event(%Fulfill{ }, state) do
    # Try a fulfillment in response to a prediction error -
    # It might instantiate a temporary model believer for a fulfillment action
    #
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end


end