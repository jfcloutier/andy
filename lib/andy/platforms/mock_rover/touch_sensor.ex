defmodule Andy.MockRover.TouchSensor do
  @moduledoc "A mock touch sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  def new(port) do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      port: port,
      path: "/mock/touch_sensor",
      type: :touch,
      mock: true
    }
  end

  ### Sensing

  def senses(_) do
    [:touch]
  end

  def read(sensor, _sense) do
    # TODO - get ready from andy_world
    random = Enum.random(0..10)

    value =
      cond do
        random > 0 -> :released
        true -> :pressed
      end

    {value, sensor}
  end

  def sensitivity(_sensor, _sense) do
    nil
  end
end
