defmodule Andy.BrickPi.UltrasonicSensor do
  @moduledoc "Ultrasonic sensor"
  @behaviour Andy.Sensing

  import Andy.BrickPi.Sysfs
  alias Andy.BrickPi.LegoSensor

  @distance_cm "US-DIST-CM"

  ### Sensing behaviour

  def senses(_) do
    # distance is in centimeters
    [:distance]
  end

  def read(sensor, sense) do
    do_read(sensor, sense)
  end

  defp do_read(sensor, :distance) do
    distance(sensor)
  end

  def pause(_) do
    500
  end

  def sensitivity(_sensor, :distance) do
    2
  end

  ####

  @doc "Get distance in centimeters - 0 to 2550"
  def distance(sensor) do
    updated_sensor = set_distance_mode(sensor)
    value = get_attribute(updated_sensor, "value0", :integer)
    {round(value / 10), updated_sensor}
  end

  defp set_distance_mode(sensor) do
    LegoSensor.set_mode(sensor, @distance_cm)
  end
end
