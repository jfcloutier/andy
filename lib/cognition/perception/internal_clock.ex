defmodule Andy.InternalClock do
  @moduledoc "An internal clock"

  require Logger
  alias Andy.{ Percept, PubSub }
  import Andy.Utils, only: [tick_interval: 0, now: 0, listen_to_events: 2]
  use Agent

  @behaviour Andy.CognitionAgentBehaviour

  @name __MODULE__

  def start_link(_) do
    { :ok, pid } = Agent.start_link(
      fn () ->
        %{ responsive: false, tock: nil, count: 0 }
      end,
      [name: @name]
    )
    Process.register(spawn(fn -> tick_tock() end), :tick_tock)
    Logger.info("#{@name} started")
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  def tick() do
    Agent.update(
      @name,
      fn (state) ->
        if state.responsive do
          tock = now()
          Logger.info("tick")
          PubSub.notify_tick()
          Percept.new_transient(
            about: %{
              class: :sensor,
              port: nil,
              type: :timer,
              sense: :time_elapsed
            },
            value: %{
              delta: tock - state.tock,
              count: state.count
            }
          )
          |> PubSub.notify_perceived()
          %{ state | tock: tock, count: state.count + 1 }
        else
          # Logger.debug(" no tick")
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
        pause(state)
      end
    )
  end

  @doc "Resume producing percepts"
  def resume() do
    Logger.info("Resuming clock")
    Agent.update(
      @name,
      fn (state) ->
        resume(state)
      end
    )
  end

   ### Cognition Agent Behaviour

  def handle_event(:faint, state) do
    pause(state)
    state
  end

  def handle_event(:revive, state) do
    resume(state)
    state
  end

  def handle_event(_event, state) do
   # Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

   ### Private

  defp pause(state) do
    Logger.info("Pausing clock")
    %{ state | responsive: false }
  end

  defp resume(state) do
    %{ state | responsive: true, tock: now() }
  end

  defp tick_tock() do
    Process.sleep(tick_interval())
    tick()
    tick_tock()
  end

end
