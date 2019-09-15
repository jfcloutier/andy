defmodule Andy.Rover.Actuation do
  @moduledoc "Provides the configurations of all rover actuators to be activated"

  require Logger

  alias Andy.{ActuatorConfig, MotorSpec, LEDSpec, SoundSpec, Activation, Script}
  import Andy.Utils

  @doc "Give the configurations of all Rover actuators"
  def actuator_configs() do
    [
      ActuatorConfig.new(
        name: :locomotion,
        type: :motor,
        # to find and name motors from specs
        specs: [
          %MotorSpec{name: :left_wheel, port: "outA"},
          %MotorSpec{name: :right_wheel, port: "outB"}
        ],
        # scripted actions to be taken upon receiving intents
        activations: [
          %Activation{
            intent: :go_forward,
            script: going_forward()
          },
          %Activation{
            intent: :go_backward,
            script: going_backward()
          },
          %Activation{
            intent: :turn_right,
            script: turning_right()
          },
          %Activation{
            intent: :turn_left,
            script: turning_left()
          },
          %Activation{
            intent: :turn,
            script: turning()
          },
          %Activation{
            intent: :stop,
            script: stopping()
          },
          %Activation{
            intent: :move,
            script: moving()
          },
          %Activation{
            intent: :panic,
            script: panicking()
          },
          %Activation{
            intent: :wait,
            script: waiting()
          }
        ]
      ),
      ActuatorConfig.new(
        name: :manipulation,
        type: :motor,
        specs: [
          %MotorSpec{name: :mouth, port: "outC"}
        ],
        activations: [
          %Activation{
            intent: :eat,
            script: eating()
          }
        ]
      ),
      ActuatorConfig.new(
        name: :leds,
        type: :led,
        specs: [
          %LEDSpec{name: :lb, position: :left, color: :blue}
        ],
        activations: [
          %Activation{
            intent: :blue_lights,
            script: blue_lights()
          }
        ]
      ),
      ActuatorConfig.new(
        name: :sounds,
        type: :sound,
        specs: [
          %SoundSpec{
            name: :loud_speech,
            type: :speech,
            props: %{
              volume: :loud,
              speed: :normal,
              voice: get_voice()
            }
          }
        ],
        activations: [
          %Activation{
            intent: :say,
            script: say()
          }
        ]
      )
    ]
  end

  # locomotion

  defp going_forward() do
    fn intent, motors ->
      rps_speed = speed(intent.value.speed)
      how_long = round(intent.value.time * 1000)

      Script.new(:going_forward, motors)
      |> Script.add_step(:right_wheel, :set_speed, [:rps, rps_speed * -1])
      |> Script.add_step(:left_wheel, :set_speed, [:rps, rps_speed * -1])
      |> Script.add_step(:all, :run_for, [how_long])

      # 			|> Script.add_wait(how_long)
    end
  end

  defp speed(kind) do
    case kind do
      :very_fast -> very_fast_rps()
      :fast -> fast_rps()
      :normal -> normal_rps()
      :slow -> slow_rps()
      :very_slow -> very_slow_rps()
      :zero -> 0
    end
  end

  defp going_backward() do
    fn intent, motors ->
      rps_speed = speed(intent.value.speed)
      how_long = round(intent.value.time * 1000)

      Script.new(:going_backward, motors)
      |> Script.add_step(:right_wheel, :set_speed, [:rps, rps_speed])
      |> Script.add_step(:left_wheel, :set_speed, [:rps, rps_speed])
      |> Script.add_step(:all, :run_for, [how_long])
    end
  end

  defp turning_right() do
    fn intent, motors ->
      how_long = round(intent.value * 1000)

      Script.new(:turning_right, motors)
      |> Script.add_step(:left_wheel, :set_speed, [:rps, -1 * speed(:normal)])
      |> Script.add_step(:right_wheel, :set_speed, [:rps, speed(:normal)])
      |> Script.add_step(:all, :run_for, [how_long])
    end
  end

  defp turning_left() do
    fn intent, motors ->
      how_long = round(intent.value * 1000)

      Script.new(:turning_left, motors)
      |> Script.add_step(:right_wheel, :set_speed, [:rps, -1 * speed(:normal)])
      |> Script.add_step(:left_wheel, :set_speed, [:rps, speed(:normal)])
      |> Script.add_step(:all, :run_for, [how_long])
    end
  end

  defp turning() do
    fn intent, motors ->
      how_long = round(intent.value.turn_time * 1000)
      direction = intent.value.turn_direction

      toggle =
        case direction do
          :right -> 1
          :left -> -1
        end

      Script.new(:turning, motors)
      |> Script.add_step(:left_wheel, :set_speed, [:rps, -1 * speed(:normal) * toggle])
      |> Script.add_step(:right_wheel, :set_speed, [:rps, speed(:normal) * toggle])
      |> Script.add_step(:all, :run_for, [how_long])
    end
  end

  defp moving() do
    fn intent, motors ->
      forward_rps_speed = speed(intent.value.forward_speed)
      forward_time_ms = round(intent.value.forward_time * 1000)
      turn_direction = intent.value.turn_direction
      turn_time_ms = round(intent.value.turn_time * 1000)
      script = Script.new(:moving, motors)

      script =
        case turn_direction do
          :right ->
            script
            |> Script.add_step(:left_wheel, :set_speed, [:rps, -1 * speed(:normal)])
            |> Script.add_step(:right_wheel, :set_speed, [:rps, speed(:normal)])

          :left ->
            script
            |> Script.add_step(:left_wheel, :set_speed, [:rps, speed(:normal)])
            |> Script.add_step(:right_wheel, :set_speed, [:rps, -1 * speed(:normal)])
        end

      script
      |> Script.add_step(:all, :run_for, [turn_time_ms])
      |> Script.add_wait(500)
      |> Script.add_step(:right_wheel, :set_speed, [:rps, forward_rps_speed * -1])
      |> Script.add_step(:left_wheel, :set_speed, [:rps, forward_rps_speed * -1])
      |> Script.add_step(:all, :run_for, [forward_time_ms])
    end
  end

  defp panicking() do
    fn intent, motors ->
      script = Script.new(:panicking, motors)
      back_off_speed = intent.value.back_off_speed
      back_off_time = intent.value.back_off_time
      turn_time = intent.value.turn_time
      repeats = intent.value.repeats

      backward_rps_speed = speed(back_off_speed)
      backward_time_ms = round(1000 * back_off_time)
      turn_time_ms = round(1000 * turn_time)

      Enum.reduce(
        1..repeats,
        script,
        fn _n, acc ->
          turn_direction = Enum.random([:right, :left, :none])

          case turn_direction do
            :right ->
              acc
              |> Script.add_step(:left_wheel, :set_speed, [:rps, -1 * speed(:normal)])
              |> Script.add_step(:right_wheel, :set_speed, [:rps, speed(:normal)])

            :left ->
              acc
              |> Script.add_step(:right_wheel, :set_speed, [:rps, -1 * speed(:normal)])
              |> Script.add_step(:left_wheel, :set_speed, [:rps, speed(:normal)])

            :none ->
              acc
              |> Script.add_step(:right_wheel, :set_speed, [:rps, 0])
              |> Script.add_step(:left_wheel, :set_speed, [:rps, 0])
          end

          acc
          |> Script.add_step(:all, :run_for, [turn_time_ms])
          |> Script.add_wait(500)
          |> Script.add_step(:right_wheel, :set_speed, [:rps, backward_rps_speed])
          |> Script.add_step(:left_wheel, :set_speed, [:rps, backward_rps_speed])
          |> Script.add_step(:all, :run_for, [backward_time_ms])
        end
      )
    end
  end

  defp stopping() do
    fn _intent, motors ->
      Script.new(:stopping, motors)
      |> Script.add_step(:all, :coast)
      |> Script.add_step(:all, :reset)
    end
  end

  def waiting() do
    fn intent, motors ->
    sleep = intent.value.time * 1_000 |> round()
      Script.new(:waiting, motors)
      |> Script.add_wait(sleep)
    end

  end

  # manipulation

  defp eating() do
    fn _intent, motors ->
      Script.new(:eating, motors)
      |> Script.add_step(:mouth, :set_speed, [:rps, 1])
      |> Script.add_step(:mouth, :run_for, [2000])
    end
  end

  # light

  defp blue_lights() do
    fn intent, leds ->
      value =
        case intent.value do
          :on -> 255
          :off -> 0
        end

      Script.new(:blue_lights, leds)
      |> Script.add_step(:lb, :set_brightness, [value])
    end
  end

  # Sounds

  defp say() do
    fn intent, sound_players ->
      Script.new(:say, sound_players)
      |> Script.add_step(:loud_speech, :speak, [intent.value])
    end
  end
end
