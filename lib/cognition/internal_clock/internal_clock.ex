defmodule Andy.InternalClock do
  @moduledoc "An internal clock"

  require Logger
  alias Andy.{Percept, InternalCommunicator}
  import Andy.Utils, only: [tick_interval: 0]

  @behaviour Andy.CognitionAgentBehaviour

  @name __MODULE__

  def start_link() do
    {:ok, pid} = Agent.start_link(
      fn() ->
        InternalCommunicator.register(__MODULE__)
        %{responsive: false, tock: nil, count: 0}
      end,
      [name: @name]
    )
		spawn_link(fn() ->
			:timer.sleep(tick_interval())
			tick_tock()
		end)
		Logger.info("#{@name} started")
    {:ok, pid}
  end

  def tick() do
    Agent.cast(
      @name,
      fn(state) ->
        if state.responsive do
          tock = now()
          Logger.info("tick")
					InternalCommunicator.notify_tick()
          Percept.new_transient(about: :time_elapsed,
																value: %{delta: tock - state.tock, count: state.count})
          |> InternalCommunicator.notify_perceived()
          %{state | tock: tock, count: state.count + 1}
        else
					Logger.info(" no tick")
          state
        end
      end)
  end

    @doc "Stop the generation of clock tick percepts"
  def pause() do
		Agent.update(
			@name,
			fn(state) ->
        Logger.info("Pausing clock")
				  %{state | responsive: false}
			end)
  end

  @doc "Resume producing percepts"
	def resume() do
    Logger.info("Resuming clock")
		Agent.update(
			@name,
			fn(state) ->
				%{state | responsive: true, tock: now()}
			end)
	end

  ### Event handling

  def handle_event(:faint, state) do
    InternalClock.pause()
    state
  end

  def handle_event(:revive, state) do
    InternalClock.resume()
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end


  ### Private

	defp tick_tock() do
		:timer.sleep(tick_interval())
		tick()
		tick_tock()
	end

end
