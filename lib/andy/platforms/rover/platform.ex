defmodule Andy.Rover.Platform do
  @behaviour Andy.PlatformBehaviour

  @moduledoc "Module implementing smart thing platform_dispatch calls"

  alias Andy.BrickPi.{Brick, LegoSound, LegoSensor, LegoMotor, LegoLED, InfraredSensor}
  require Logger

  # 5 secs to system shutdown
  @shutdown_delay 5000

  ### PlatformBehaviour

  def start() do
    Logger.info("Starting Rover platform")
    Brick.start()
  end

  def ready?() do
    Brick.ready?()
  end

  def ports_config() do
    [
      %{port: :in1, device: :ir_seeker},
      %{port: :in2, device: :color},
      %{port: :in3, device: :infrared},
      %{port: :in4, device: :ultrasonic},
      # left
      %{port: :outA, device: :large},
      # right
      %{port: :outB, device: :large},
      # mouth
      %{port: :outC, device: :medium}
    ]
  end

  def display(words) do
    Logger.info("DISPLAY #{inspect(words)}")
  end

  def actuation_logic() do
    Andy.Rover.Actuation.actuator_configs()
  end

  @doc "The device mode for the platform"
  def device_mode(device_type) do
    case device_type do
      :infrared -> "ev3-uart"
      :touch -> "ev3-analog"
      :gyro -> "ev3-uart"
      :color -> "ev3-uart"
      :ultrasonic -> "ev3-uart"
      :ir_seeker -> "nxt-i2c"
      :large -> "tacho-motor"
      :medium -> "tacho-motor"
      :led -> "led"
    end
  end

  @doc "The device code for the platform"
  def device_code(device_type) do
    case device_type do
      :infrared -> "lego-ev3-ir"
      :touch -> "lego-ev3-touch"
      :gyro -> "lego-ev3-gyro"
      :color -> "lego-ev3-color"
      :ultrasonic -> "lego-ev3-us"
      :ir_seeker -> "ht-nxt-ir-seek-v2"
      :large -> "lego-ev3-l-motor"
      :medium -> "lego-ev3-m-motor"
    end
  end

  def device_manager(type) do
    case type do
      :motor -> LegoMotor
      :sensor -> LegoSensor
      :led -> LegoLED
      :sound -> LegoSound
    end
  end

  def sensors() do
    LegoSensor.sensors()
  end

  def motors() do
    LegoMotor.motors()
  end

  def sound_players() do
    LegoSound.sound_players()
  end

  def lights() do
    LegoLED.leds()
  end

  def shutdown() do
    Logger.info("Shutting down")
    Process.sleep(@shutdown_delay)
    Application.stop(:andy)
    # 		System.cmd("poweroff", [])
  end

  def voice() do
    "en-sc"
  end

  def sensor_read_sense(device, sense) do
    LegoSensor.read(device, sense)
  end

  def motor_read_sense(device, sense) do
    LegoMotor.read(device, sense)
  end

  def sensor_sensitivity(device, sense) do
    LegoSensor.sensitivity(device, sense)
  end

  def motor_sensitivity(device, sense) do
    LegoMotor.sensitivity(device, sense)
  end

  def senses_for_id_channel(channel) do
    InfraredSensor.beacon_senses_for(channel)
  end

  def nudge(_device, _sense, value, _previous_value) do
    value
  end

  ###
end
