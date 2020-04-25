defmodule Andy.MockRover.UltrasonicSensor do
  @moduledoc "A mock ultrasonic sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  # actual max is 250 cms
  @max_distance 250

  def new(port) do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      port: port,
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
   # TODO - get ready from andy_world
   distance_cm(sensor)
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  defp distance_cm(sensor) do
    value = Enum.random(0..@max_distance)
    {value, sensor}
  end

end
