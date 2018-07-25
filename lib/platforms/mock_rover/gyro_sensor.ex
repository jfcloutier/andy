defmodule Andy.MockRover.GyroSensor do
  @moduledoc "A mock gyro sensor"

  @behaviour Andy.Sensing

	alias Andy.Device

	def new() do
    %Device{mod: __MODULE__,
						class: :sensor,
						path: "/mock/gyro_sensor",
						type: :gyro,
						mock: true}
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
  
   def nudge(_sensor, sense, value, previous_value) do
    case sense do
      :angle -> nudge_angle(value, previous_value)
      :rotational_speed -> nudge_rotational_speed(value, previous_value)
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

  def nudge_angle(value, previous_value) do
    case previous_value do
      nil -> 32767 - :rand.uniform(32767 * 2)
      _ -> value + previous_value |> max(-32767) |> min(32767)
    end
  end

  def rotational_speed(sensor) do
   value = 20 - :rand.uniform(40)
    {value, sensor}
  end

  def nudge_rotational_speed(value, previous_value) do
    case previous_value do
      nil -> 440 - :rand.uniform(440 * 2)
      _ -> value + previous_value |> max(-440) |> min(440)
    end
  end

end

  
