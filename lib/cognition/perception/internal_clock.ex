defmodule Andy.InternalClock do
  @moduledoc "An internal clock"

  require Logger
  alias Andy.{ Percept, InternalCommunicator }
  import Andy.Utils, only: [tick_interval: 0, now: 0]

  @behaviour Andy.CognitionAgentBehaviour

  @name __MODULE__

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn () ->
        register_internal()
        %{ responsive: false, tock: nil, count: 0 }
      end,
      [name: @name]
    )
    Task.async(
      fn () ->
        :timer.sleep(tick_interval())
        tick_tock()
      end
    )
    Logger.info("#{@name} started")
    { :ok, pid }
  end

  def tick() do
    Agent.cast(
      @name,
      fn (state) ->
        if state.responsive do
          tock = now()
          Logger.info("tick")
          InternalCommunicator.notify_tick()
          Percept.new_transient(
            about: %{class: :sensor, port: nil, type: :timer, sense: :time_elapsed},
            value: %{
              delta: tock - state.tock,
              count: state.count
            }
          )
          |> InternalCommunicator.notify_perceived()
          %{ state | tock: tock, count: state.count + 1 }
        else
 #         Logger.debug(" no tick")
          state
        end
      end
    )
  end

  @doc "Stop the generation of clock tick percepts"
  def pause() do
    Agent.update(
      @name,
      fn (state) ->
        Logger.info("Pausing clock")
        %{ state | responsive: false }
      end
    )
  end

  @doc "Resume producing percepts"
  def resume() do
    Logger.info("Resuming clock")
    Agent.update(
      @name,
      fn (state) ->
        %{ state | responsive: true, tock: now() }
      end
    )
  end

  ### Cognition Agent Behaviour

  def handle_event(:faint, state) do
    pause()
    state
  end

  def handle_event(:revive, state) do
    resume()
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  def register_internal() do
    InternalCommunicator.register(__MODULE__)
  end


  ### Private

  defp tick_tock() do
    :timer.sleep(tick_interval())
    tick()
    tick_tock()
  end

end
