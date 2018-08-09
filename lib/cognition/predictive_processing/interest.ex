defmodule Andy.Interest do
  @moduledoc """
  Responsible for modulating the effective precisions of predictors
  based on the relative priorities of the models currently being realized.
  """

  require Logger
  alias Andy.{ PubSub }

  @name __MODULE__

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
    { :ok, pid } = Agent.start_link(
      fn ->
        register_internal()
        %{
          # %{predictor_name: [{successes, failures}, nil, nil]}
          # TODO
        }
      end,
      [name: @name]
    )
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  # TODO

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

end