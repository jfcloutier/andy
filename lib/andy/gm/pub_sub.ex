defmodule Andy.GM.PubSub do
  @moduledoc """
  Enables embodied agents to communicate via broadcasted events,
  without knowing of one another
  """

  require Logger
  import Andy.Utils

  @registry_name :registry
  # single topic for all subscribers
  @topic :pp

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @doc "Start the registry"
  def start_link() do
    Logger.info("Starting #{__MODULE__}")

    Registry.start_link(
      keys: :duplicate,
      name: @registry_name,
      partitions: System.schedulers_online()
    )
  end

  @doc "Register a subscriber"
  def register(module) do
    Logger.info("Registering process #{inspect(self())} on module #{module} to pubsub")
    Registry.register(@registry_name, @topic, module)
  end

  @doc "Notify after a delay"
  def notify_after(event, delay) do
    spawn(fn ->
      Process.sleep(delay)
      notify(event)
    end)
  end

  @doc "Notify of a shutdown request"
  def notify_shutdown() do
    notify(:shutdown)
    platform_dispatch(:shutdown)
  end

  @doc "Notify of a new intent"
  def notify_intended(intent) do
    notify({:intended, intent})
  end

  @doc "Notify of an intent actuated"
  def notify_actuated(intent) do
    notify({:actuated, intent})
  end

  @doc "The registry name"
  def registry_name() do
    @registry_name
  end

  # Dispatch the handling of an event to all subscribing embodied cognition agents
  def notify(event) do
    Logger.info("Notify #{inspect(event)}")

    spawn(fn ->
      Registry.dispatch(
        @registry_name,
        @topic,
        fn subscribers ->
          for {pid, module} <- subscribers,
              do:
                Agent.cast(
                  pid,
                  fn state ->
                    # Logger.debug("SENDING event #{inspect event} to #{module} at #{inspect pid}")
                    apply(module, :handle_event, [event, state])
                  end
                )
        end
      )
    end)

    :ok
  end
end
