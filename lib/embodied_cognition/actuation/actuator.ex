defmodule Andy.Actuator do
  @moduledoc "An actuator that translates intents into commands sent to motors"

  require Logger

  alias Andy.{
    Script,
    Device,
    MotorSpec,
    LEDSpec,
    SoundSpec,
    CommSpec,
    Communicators,
    PubSub,
    Intent
  }

  import Andy.Utils

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([actuator_config]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: {__MODULE__, :start_link, [actuator_config]}
    }
  end

  @doc "Start an actuator from a configuration"
  def start_link(actuator_config) do
    Logger.info("Starting #{__MODULE__} #{actuator_config.name}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          devices =
            case actuator_config.type do
              :motor ->
                find_motors(actuator_config.specs)

              :led ->
                find_leds(actuator_config.specs)

              :sound ->
                find_sound_players(actuator_config.specs)

              :comm ->
                find_communicators(actuator_config.specs)
            end

          %{
            actuator_config: actuator_config,
            devices: devices,
            name: actuator_config.name
          }
        end,
        name: actuator_config.name
      )

    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  def realize_intent(intent, %{name: name, actuator_config: actuator_config} = state) do
    Logger.info("Realizing intent #{inspect(intent)}")

    if check_freshness(name, intent) do
      actuator_config.activations
      |> Enum.filter(fn activation -> activation.intent == intent.about end)
      |> Enum.map(fn activation -> activation.script end)
      |> Enum.each(
        # execute activated script sequentially
        fn script_generator ->
          script = script_generator.(intent, state.devices)
          Script.execute(actuator_config.type, script)

          # This will have the intent stored in memory. Unrealized intents are not retained in memory.
          PubSub.notify_actuated(intent)
        end
      )
    end
  end

  ### Cognition agent

  def handle_event({:intended, intent}, %{actuator_config: actuator_config} = state) do
    if intent.about in actuator_config.intents do
      realize_intent(intent, state)
    end

    state
  end

  def handle_event(_event, state) do
    # 		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### Private

  defp check_freshness(name, intent) do
    age = Intent.age(intent)
    factor = if intent.strong, do: strong_intent_factor(), else: 1

    if age > max_intent_age() * factor do
      Logger.warn("STALE #{Intent.strength(intent)} intent #{inspect(intent.about)} #{age}")
      PubSub.notify_overwhelmed(:actuator, name)
      false
    else
      true
    end
  end

  defp find_motors(motor_specs) do
    all_motors = platform_dispatch(:motors)

    found =
      Enum.reduce(
        motor_specs,
        %{},
        fn motor_spec, acc ->
          motor =
            Enum.find(
              all_motors,
              &MotorSpec.matches?(motor_spec, &1)
            )

          if motor == nil do
            Logger.warn(
              "Motor not found matching #{inspect(motor_spec)} in #{inspect(all_motors)}"
            )

            acc
          else
            Map.put(acc, motor_spec.name, update_props(motor, motor_spec.props))
          end
        end
      )

    found
  end

  defp find_leds(led_specs) do
    all_leds = platform_dispatch(:lights)

    found =
      Enum.reduce(
        led_specs,
        %{},
        fn led_spec, acc ->
          led =
            Enum.find(
              all_leds,
              &LEDSpec.matches?(led_spec, &1)
            )

          if led == nil do
            Logger.warn("LED not found matching #{inspect(led_spec)} in #{inspect(all_leds)}")
            acc
          else
            Map.put(acc, led_spec.name, update_props(led, led_spec.props))
          end
        end
      )

    found
  end

  defp find_sound_players(sound_specs) do
    all_sound_players = platform_dispatch(:sound_players)

    found =
      Enum.reduce(
        sound_specs,
        %{},
        fn sound_spec, acc ->
          sound_player =
            Enum.find(
              all_sound_players,
              &SoundSpec.matches?(sound_spec, &1)
            )

          if sound_player == nil do
            Logger.warn(
              "Sound player not found matching #{inspect(sound_spec)} in #{
                inspect(all_sound_players)
              }"
            )

            acc
          else
            Map.put(acc, sound_spec.name, update_props(sound_player, sound_spec.props))
          end
        end
      )

    found
  end

  defp find_communicators(comm_specs) do
    all_communicators = Communicators.communicators()

    found =
      Enum.reduce(
        comm_specs,
        %{},
        fn comm_spec, acc ->
          communicator =
            Enum.find(
              all_communicators,
              &CommSpec.matches?(comm_spec, &1)
            )

          if communicator == nil do
            Logger.warn(
              "Communicator not found matching #{inspect(comm_spec)} in #{
                inspect(all_communicators)
              }"
            )

            acc
          else
            Map.put(acc, comm_spec.name, update_props(communicator, comm_spec.props))
          end
        end
      )

    found
  end

  defp update_props(device, props) do
    Enum.reduce(
      Map.keys(props),
      device,
      fn key, dev ->
        %Device{dev | props: Map.put(dev.props, key, Map.get(props, key, nil))}
      end
    )
  end
end
