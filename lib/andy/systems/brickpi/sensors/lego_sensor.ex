defmodule Andy.BrickPi.LegoSensor do
  @moduledoc "Lego sensor access."

  require Logger
  import Andy.BrickPi.Sysfs
  alias Andy.Device

  alias Andy.BrickPi.{
    ColorSensor,
    TouchSensor,
    InfraredSensor,
    UltrasonicSensor,
    GyroSensor,
    IRSeekerSensor
  }

  @sys_path "/sys/class/lego-sensor"
  @prefix "sensor"
  @driver_regex ~r/(lego-ev3|ht-nxt)-(?<sensor>.+)/i
  @mode_switch_delay 100

  @doc "Get the currently connected lego sensors"
  def sensors() do
    files =
      case File.ls(@sys_path) do
        {:ok, files} ->
          files

        {:error, reason} ->
          Logger.warn("Failed getting sensor files: #{inspect(reason)}")
          []
      end

    files
    |> Enum.filter(&String.starts_with?(&1, @prefix))
    |> Enum.map(&init_sensor("#{@sys_path}/#{&1}"))
  end

  @doc "Is this type of device a sensor?"
  def sensor?(device_type) do
    device_type in [:touch, :infrared, :color, :ultrasonic, :gyro, :ir_seeker]
  end

  @doc "Get the list of senses from a sensor"
  def senses(sensor) do
    apply(module_for(sensor), :senses, [sensor])
  end

  @doc "Read the value of a sense from a sensor"
  # {value, updated_sensor} - value can be nil
  def read(sensor, sense) do
    try do
      apply(module_for(sensor), :read, [sensor, sense])
    rescue
      error ->
        Logger.warn("#{inspect(error)} when reading #{inspect(sense)} from #{inspect(sensor)}")
        {nil, sensor}
    end
  end

  @doc "Get how long to pause between reading a sense from a sensor. In msecs"
  def pause(sensor) do
    apply(module_for(sensor), :pause, [sensor])
  end

  @doc "Get the resolution of a sensor (the delta between essentially identical readings). Nil or an integer."
  def sensitivity(sensor, sense) do
    apply(module_for(sensor), :sensitivity, [sensor, sense])
  end

  @doc "Is this the ultrasonic sensor?"
  def ultrasonic?(sensor) do
    sensor.type == :ultrasonic
  end

  @doc "Is this the gyro sensor?"
  def gyro?(sensor) do
    sensor.type == :gyro
  end

  @doc "Is this the color sensor?"
  def color?(sensor) do
    sensor.type == :color
  end

  @doc "Is this the touch sensor?"
  def touch?(sensor) do
    sensor.type == :touch
  end

  @doc "Is this the infrared sensor?"
  def infrared?(sensor) do
    sensor.type == :infrared
  end

  @doc "Is this the IR seeker sensor?"
  def ir_seeker?(sensor) do
    sensor.type == :ir_seeker
  end

  @doc "Set the sensor's mode"
  def set_mode(sensor, mode) do
    if mode(sensor) != mode do
      Logger.info("Switching mode of #{sensor.path} to #{inspect mode} from #{inspect mode(sensor)}")
      set_attribute(sensor, "mode", mode)
      # Give time for the mode switch
      :timer.sleep(@mode_switch_delay)

      case get_attribute(sensor, "mode", :string) do
        same_mode when same_mode == mode->
          %Device{sensor | props: %{sensor.props | mode: mode}}

        other ->
          Logger.warn("Mode is still #{other}. Retrying to set mode to #{mode}")
          :timer.sleep(@mode_switch_delay)
          set_mode(sensor, mode)
      end
    else
      sensor
    end
  end

  @doc "Get the sensor mode"
  def mode(sensor) do
    sensor.props.mode
  end

  #### PRIVATE

  defp module_for(sensor) do
    module_for_type(sensor.type)
  end

  defp module_for_type(type) do
    case type do
      :touch -> TouchSensor
      :color -> ColorSensor
      :infrared -> InfraredSensor
      :ultrasonic -> UltrasonicSensor
      :ir_seeker -> IRSeekerSensor
      :gyro -> GyroSensor
    end
  end

  defp init_sensor(path) do
    port_name = read_sys(path, "address")
    driver_name = read_sys(path, "driver_name")
    %{"sensor" => type_name} = Regex.named_captures(@driver_regex, driver_name)

    type =
      case type_name do
        "us" -> :ultrasonic
        "gyro" -> :gyro
        "color" -> :color
        "touch" -> :touch
        "ir" -> :infrared
        "ir-seek-v2" -> :ir_seeker
      end

    sensor = %Device{
      mod: module_for_type(type),
      class: :sensor,
      path: path,
      port: port_name,
      type: type
    }

    mode = get_attribute(sensor, "mode", :string)
    %Device{sensor | props: %{mode: mode}}
  end
end
