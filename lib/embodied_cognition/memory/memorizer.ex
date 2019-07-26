defmodule Andy.Memorizer do
  @moduledoc "The agent responsible for putting things into Memory"

  alias Andy.Memory
  import Andy.Utils
  require Logger

  @name __MODULE__

  @behaviour Andy.EmbodiedCognitionAgent

  ### API

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @doc "Start the memory server"
  def start_link() do
    Logger.info("Starting #{@name}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %{}
        end,
        name: @name
      )

    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  ### Cognitive Agent behaviour

  def handle_event({:perceived, percept}, state) do
    if not percept.transient do
      Memory.store(percept)
    end

    state
  end

  # Intends are memorized only when realized by actuators
  # {:intended, intent} events are ignored
  def handle_event({:actuated, intent}, state) do
    Memory.store(intent)
    state
  end

  def handle_event({:believed, belief}, state) do
    Memory.store(belief)
    state
  end

  def handle_event(_event, state) do
    # 		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end
end
