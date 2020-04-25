defmodule Andy.MockRover.IRSeekerSensor do
  @moduledoc "A mock infrared seeker sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  def new(port) do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      port: port,
      path: "/mock/ir_seeker",
      type: :ir_seeker,
      mock: true
    }
  end

  ### Sensing

  def senses(_) do
    [:direction, :direction_mod, :proximity, :proximity_mod]
  end

  def read(sensor, sense) when sense in [:direction, :direction_mod] do
    # TODO - get ready from andy_world
    direction(sensor)
  end

  def read(sensor, sense) when sense in [:proximity, :proximity_mod] do
    # TODO - get ready from andy_world
    proximity(sensor)
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  defp direction(sensor) do
    value = Enum.random(0..9)

    angle =
      cond do
        value == 0 ->
          :unknown

        value < 5 ->
          (5 - value) * -30

        value == 5 ->
          0

        value > 5 ->
          (value - 5) * 30
      end

    {angle, sensor}
  end

  defp proximity(sensor) do
    proximity = Enum.random(0..9)
    {proximity, sensor}
  end
end
