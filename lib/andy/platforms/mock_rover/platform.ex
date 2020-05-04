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

  alias Andy.{Device, SoundPlayer}
  require Logger

  ### PlatformBehaviour

  def start() do
    name = Andy.name()
    %{row: row, column: column, orientation: orientation} = start_state = start_state(name)

    :ok =
      GenServer.call(
        {:global, :playground},
        {:place_robot,
         name: name,
         node: node(),
         row: row,
         column: column,
         orientation: orientation,
         sensor_data: sensor_data(),
         motor_data: motor_data()}
      )

    Logger.info("Platform mock_rover #{name} placed at #{inspect(start_state)}")
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
    apply(device.mod, :read, [device, sense])
  end

  def motor_read_sense(%Device{mock: true} = device, sense) do
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

  ### PRIVATE

  defp start_state(name) do
    start = Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:start) |> Map.fetch!(name)
    Logger.info("#{name} is starting with #{inspect(start)}")
    start
  end

  defp sensor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:sensor_state)
  end

  defp motor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:motor_state)
  end



end
