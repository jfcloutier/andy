defmodule Andy.Clock do
  @moduledoc """
  The biological clock. It can be paused and resumed.
  """

  use GenServer
  require Logger
  alias __MODULE__

  # every 100th of a sec
  @tick 10
  # wait 1 sec if paused
  @wait_duration 1000

  def start_link(_) do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(Clock, :ok, name: :clock)
  end

  @impl true
  def init(_) do
    Process.send_after(self(), :advance, @tick)
    now = :os.system_time(:millisecond)
    {:ok, %{time: now, paused: true, dilatation: 0}}
  end

  def now() do
    GenServer.call(:clock, :now)
  end

  def dilate(dilatation) do
    GenServer.cast(:clock, {:dilate, dilatation})
  end

  def paused?() do
    GenServer.call(:clock, :paused?)
  end

  def pause() do
    GenServer.cast(:clock, :pause)
  end

  def resume() do
    GenServer.cast(:clock, :resume)
  end

  def wait(msecs) do
    GenServer.call(:clock, {:wait, msecs})
  end

  def wait_while_paused() do
    if paused?() do
      Process.sleep(@wait_duration)
      wait_while_paused()
    end
  end

  @impl true
  def handle_call(:now, _from, %{time: time} = state) do
    {:reply, time, state}
  end

  def handle_call(:paused?, _from, %{paused: paused?} = state) do
    {:reply, paused?, state}
  end

  def handle_call({:wait, msecs}, _from, %{dilatation: dilatation} = state) do
    {:reply, max(msecs, msecs * dilatation), state}
  end

  @impl true
  def handle_cast(:pause, state) do
    Logger.warn("PAUSING CLOCK")
    {:noreply, %{state | paused: true}}
  end

  def handle_cast(:resume, state) do
    Logger.warn("RESUMING CLOCK")
    Process.send_after(self(), :advance, @wait_duration)
    {:noreply, %{state | paused: false}}
  end

  def handle_cast({:dilate, dilatation}, state) do
    {:noreply, %{state | dilatation: dilatation}}
  end

  @impl true
  def handle_info(:advance, %{time: time, paused: paused?, dilatation: dilatation} = state) do
    if paused? do
      {:noreply, state}
    else
      Process.send_after(self(), :advance, max(@tick, @tick * dilatation))
      {:noreply, %{state | time: time + @tick}}
    end
  end
end
