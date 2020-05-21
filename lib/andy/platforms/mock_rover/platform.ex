defmodule Andy.MockRover.Platform do
  @moduledoc "The mock ROVER platform"

  @behaviour Andy.PlatformBehaviour

  alias Andy.MockRover.{
    ColorSensor,
    InfraredSensor,
    IRSeekerSensor,
    UltrasonicSensor,
    Tachomotor,
    LED
  }

  alias Andy.{Device, SoundPlayer, AndyWorldGateway}
  require Logger

  ### PlatformBehaviour

  def start() do
    # Start
    :ok
  end

  def ready?() do
    true
  end

  def ports_config() do
    []
  end

  def display(words) do
    Logger.info("DISPLAYING: #{words}")
  end

  def actuation_logic() do
    # Use Rover's actuation
    Andy.Rover.Actuation.actuator_configs()
  end

  def device_mode(_device_type) do
    "mock"
  end

  def device_code(device_type) do
    case device_type do
      :infrared -> "mock-ir"
      :ir_seeker -> "mock-seek"
      :touch -> "mock-touch"
      :gyro -> "mock-gyro"
      :color -> "mock-color"
      :ultrasonic -> "mock-us"
      :large -> "mock-l-motor"
      :medium -> "mock-m-motor"
    end
  end

  def device_manager(_type) do
    # itself for all mock devices
    __MODULE__
  end

  def sensors() do
    [
      # TouchSensor.new(nil),
      ColorSensor.new("in2"),
      InfraredSensor.new("in3"),
      IRSeekerSensor.new("in1"),
      UltrasonicSensor.new("in4")
      # GyroSensor.new(nil)
    ]
  end

  def motors() do
    [
      Tachomotor.new(:large, "outA"),
      Tachomotor.new(:large, "outB"),
      Tachomotor.new(:medium, "outC")
    ]
  end

  def sound_players() do
    [SoundPlayer.new()]
  end

  def lights() do
    [
      LED.new(:blue, :left)
    ]
  end

  def shutdown() do
    Logger.info("Shutting down")
    # TODO - remove robot from andy_world's playground
    Process.sleep(3000)
    Application.stop(:andy)
  end

  def voice() do
    "en-sc"
  end

  def sensor_read_sense(%Device{mock: true} = device, sense) do
    AndyWorldGateway.read_sense(device, sense)
    # apply(device.mod, :read, [device, sense])
  end

  def motor_read_sense(%Device{mock: true} = device, sense) do
    # Not yet simulated in AndyWorld
    apply(device.mod, :read, [device, sense])
  end

  def sensor_sensitivity(%Device{mock: true} = device, sense) do
    apply(device.mod, :sensitivity, [device, sense])
  end

  def motor_sensitivity(%Device{mock: true} = device, sense) do
    apply(device.mod, :sensitivity, [device, sense])
  end

  def senses_for_id_channel(channel) do
    [{:beacon_heading, channel}, {:beacon_distance, channel}, {:beacon_on, channel}]
  end

  def execute_command(%Device{mock: true} = device, command, params) do
    apply(device.mod, command, [device | params])
  end
end
