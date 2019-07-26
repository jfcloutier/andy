defmodule Andy.MockRover.UltrasonicSensor do
  @moduledoc "A mock ultrasonic sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  # actual max is 2550 cms
  @max_distance 100
  @nudge_distance 10

  def new() do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      path: "/mock/ultrasonic_sensor",
      type: :ultrasonic,
      mock: true
    }
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
    value = Enum.random(0..@max_distance)
    {value, sensor}
  end

  defp nudge_distance_cm(value, previous_value) do
    if previous_value == nil do
      value
    else
      direction = if value - previous_value >= 0, do: 1, else: -1
      nudge = Enum.random(0..@nudge_distance)

      (previous_value + direction * nudge)
      |> max(0)
      |> min(@max_distance)
    end
  end
end
