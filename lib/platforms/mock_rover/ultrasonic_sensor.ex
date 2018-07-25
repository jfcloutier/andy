defmodule Andy.MockRover.UltrasonicSensor do
  @moduledoc "A mock ultrasonic sensor"

  @behaviour Andy.Sensing

	alias Andy.Device

  def new() do
    %Device{mod: __MODULE__,
						class: :sensor,
            path: "/mock/ultrasonic_sensor",
            type: :ultrasonic,
            mock: true}
  end

  ### Sensing

  def senses(_) do
    [:distance]
  end

  def read(sensor, :distance) do
    distance_cm(sensor)
  end

  def nudge(_sensor, :distance, value, previous_value) do
    nudge_distance_cm(value, previous_value)
  end
	
  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  defp distance_cm(sensor) do
    value = 10 - :rand.uniform(30)
    {value, sensor}
  end

  defp nudge_distance_cm(value, previous_value) do
    case previous_value do
      nil -> :rand.uniform(2550)
      _ -> (value + previous_value) |> max(0) |> min(2550)
    end
  end

end
