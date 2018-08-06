defmodule Andy.Attention do
  @moduledoc "Responsible for polling detectors as needed by predictors"

  require Logger
  alias Andy.{ PubSub }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    {:ok, pid } = Agent.start_link(
    fn ->
    register_internal()
    # detector_spec => [perceptor_id, ...]
    %{}
    end
    )
  end

  def pay_attention(detector_specs, predictor_pid) do
    # TODO
  end

  def lose_attention(predictor_pid) do
    # TODO
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  ## Handle timer events

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

end