defmodule Andy.PubSub do
  @moduledoc """
  Enables embodied agents to communicate via broadcasted events,
  without knowing of one another
  """

  require Logger
  import Andy.Utils

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
    Logger.info("Starting #{__MODULE__}")
    Registry.start_link(
      keys: :duplicate,
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
    Logger.info("Registering process #{inspect self()} on module #{module} to pubsub")
    Registry.register(@registry_name, @topic, module)
  end

  @doc "Notify of a shutdown request"
  def notify_shutdown() do
    platform_dispatch(:shutdown)
  end

  @doc "Notify of clock tick"
  def notify_tick() do
    notify(:tick)
  end

  @doc "Notify of a new percept"
  def notify_perceived(percept) do
    notify({ :perceived, percept })
  end

  @doc "Notify of a new intent"
  def notify_intended(intent) do
    notify({ :intended, intent })
  end

  @doc "Notify of an intent actuated"
  def notify_actuated(intent) do
    notify({ :actuated, intent })
  end

  @doc "Notify of a belief"
  def notify_believed(belief) do
    notify({ :believed, belief })
  end

  @doc "Notify of a percept memorized"
  def notify_percept_memorized(percept) do
    notify({ :percept_memorized, percept })
  end

  @doc "Notify of an intent memorized"
  def notify_intent_memorized(intent) do
    notify({ :intent_memorized, intent })
  end

  @doc "Notify of a belief memorized"
  def notify_belief_memorized(belief) do
    notify({ :belief_memorized, belief })
  end

  @doc "Notify of a prediction error"
  def notify_prediction_error(prediction_error) do
    notify({ :prediction_error, prediction_error })
  end

  @doc "Notify of a prediction fulfilled"
  def notify_prediction_fulfilled(prediction_fulfilled) do
    notify({ :prediction_fulfilled, prediction_fulfilled })
  end

  @doc "Notify that a predictor is paying attention to some detection"
  def notify_attention_on(detector_specs, predictor_name, precision) do
    notify({ :attention_on, detector_specs, predictor_name, precision })
  end

  @doc "Notify that a predictor is no longer paying attention"
  def notify_attention_off(predictor_pid) do
    notify({ :attention_off, predictor_pid })
  end

  @doc "Notify that a predictor is to use a given fulfillment"
  def notify_fulfill(fulfill) do
    notify({ :fulfill, fulfill })
  end

  @doc "Notify that a model was believed or not as predicted"
  def notify_believed_as_predicted(model_name, prediction_name, believed?) do
    notify({ :believed_as_predicted, model_name, prediction_name, believed? })
  end

  @doc "Notify that a believer started on a model"
  def notify_believer_started(model_name) do
    notify({ :believer_started, model_name })
  end

  @doc "Notify that a believer terminated on a model"
  def notify_believer_terminated(model_name) do
    notify({ :believer_terminated, model_name })
  end

  @doc "Notify that a model has been deprioritized"
  def notify_model_deprioritized(model_name, priority) do
    notify({ :model_deprioritized, model_name, priority })
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
    { :ok, paused? } = Registry.meta(@registry_name, :paused)
    paused? == true
  end

  @doc "Is the robot overwhelmed?"
  def overwhelmed?() do
    { :ok, overwhelmed? } = Registry.meta(@registry_name, :overwhelmed)
    overwhelmed? == true
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

  # Dispatch the handling of an event to all subscribing embodied cognition agents
  defp notify(event) do
    Logger.info("Notify #{inspect event}")
    spawn(
      fn ->
        Registry.dispatch(
          @registry_name,
          @topic,
          fn (subscribers) ->
            for { pid, module } <- subscribers,
                do: Agent.cast(
                  pid,
                  fn (state) ->
                    Logger.info("SENDING event #{inspect event} to #{module} at #{inspect pid}")
                    apply(module, :handle_event, [event, state])
                  end
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
    spawn(
      fn () -> # make sure to revive
        :timer.sleep(msecs)
        notify_revive()
      end
    )
  end

end
