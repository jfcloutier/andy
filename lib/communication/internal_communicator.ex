defmodule Andy.InternalCommunicator do
  @moduledoc "Enables embodied cognition agents to communicate via pub sub"

  require Logger
  import Andy.Utils
  alias Andy.Percept

  @registry_name :registry
  @topic :pp # single topic for all subscribers
  @faint_duration 2500

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the registry"
  def start_link() do
    Registry.start_link(
      keys: :unique,
      name: @registry_name,
      partitions: System.schedulers_online(),
      meta: [
        when_started: now(),
        overwhelmed: false,
        paused: false
      ]
    )
  end

  @doc "Register a subscriber"
  def register(module) do
    Registry.register(@registry_name, @topic, module)
  end

  @doc "Handle notification of a shutdown request"
  def notify_shutdown() do
    platform_dispatch(:shutdown)
  end

  @doc "Handle notification of clock tick"
  def notify_tick() do
    notify(:tick)
  end

  @doc "Handle notification of a new percept"
  def notify_perceived(percept) do
    notify({ :perceived, percept })
  end

  @doc "Handle notification of a new intent"
  def notify_intended(intent) do
    notify({ :intended, intent })
  end

  @doc "Handle notification of an intent actuated"
  def notify_realized(actuator_name, intent) do
    notify({ :actuated, actuator_name, intent })
  end

  @doc "Handle notification of a belief"
  def notify_believed(belief) do
    notify({ :believed, belief })
  end

  @doc "Handle notification of a prediction error"
  def notify_prediction_error(prediction_error) do
    notify({ :prediction_error, prediction_error })
  end

  @doc "Handle notification of a prediction fulfilled"
  def notify_prediction_fulfilled(prediction_fulfilled) do
    notify({ :prediction_fulfilled, prediction_fulfilled })
  end

  @doc "Handle notification of something memorized"
  def notify_memorized(memorization, %Percept{ } = percept) do
    notify({ :memorized, memorization, percept })
  end

  @doc "Found the id channel of another member of the community"
  def notify_id_channel(id_channel, community_name) do
    notify({ :id_channel, id_channel, community_name })
  end

  @doc "A component is overwhelmed"
  def notify_overwhelmed(component_type, name) do
    Logger.warn("OVERWHELMED - #{component_type}")
    notify({ :overwhelmed, component_type, name })
    if not overwhelmed?() and not paused?() do
      Logger.warn("FAINTING")
      notify(:faint)
      set_alarm_clock(@faint_duration)
      set_overwhelmed(true)
    else
      :ok
    end
    notify({ :notify_overwhelmed, component_type, name })
  end

  def notify_revive() do
    Logger.warn("REVIVING")
    if not paused?(), do: notify(:revive)
    set_overwhelmed(false)
  end


  @doc "Notified of new runtime stats"
  def notify_runtime_stats(stats) do
    notify({ :notify_runtime_stats, stats })
  end

  @doc "Notified of a sense polling request"
  def notify_poll(sensing_device, sense) do
    notify({ :poll, sensing_device, sense })
  end

  @doc "The registry name"
  def registry_name() do
    @registry_name
  end

  @doc "Is the robot paused?"
  def paused?() do
    Registry.meta(@registry_name, :paused)
  end

  @doc "Is the robot overwhelmed?"
  def overwhelmed?() do
    Registry.meta(@registry_name, :overwhelmed)
  end

  @doc "Toggle the robot between paused and active"
  def toggle_paused() do
    if paused?() do
      notify(:revive)
      set_paused(false)
      set_overwhelmed(false)
    else
      notify(:faint)
      set_paused(true)
    end
  end

  ### Private

  defp notify(event) do
    Task.async(
      fn ->
        Registry.dispatch(
          @registry_name,
          @topic,
          fn (subscribers) ->
            for { pid, module } <- subscribers,
                do: Agent.cast(
                  pid,
                  fn (state) -> apply(module, :handle_event, [event, state]) end
                )
          end
        )
      end
    )
  end

  defp set_paused(paused?) do
    Registry.put_meta(@registry_name, :paused, paused?)
  end

  defp set_overwhelmed(overwhelmed?) do
    Registry.put_meta(@registry_name, :overwhelmed, overwhelmed?)
  end

  defp set_alarm_clock(msecs) do
    Task.async(
      fn () -> # make sure to revive
        :timer.sleep(msecs)
        notify_revive()
      end
    )
  end

end
