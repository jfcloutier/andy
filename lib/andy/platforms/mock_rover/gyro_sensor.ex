defmodule Andy.MockRover.GyroSensor do
  @moduledoc "A mock gyro sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  def new() do
    %Device{mod: __MODULE__, class: :sensor, path: "/mock/gyro_sensor", type: :gyro, mock: true}
  end

  ### Sensing

  def senses(_) do
    [:angle, :rotational_speed]
  end

  def read(sensor, sense) do
    case sense do
      :angle -> angle(sensor)
      :rotational_speed -> rotational_speed(sensor)
    end
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  def angle(sensor) do
    value = 50 - :rand.uniform(100)
    {value, sensor}
  end

  def rotational_speed(sensor) do
    value = 20 - :rand.uniform(40)
    {value, sensor}
  end
end
