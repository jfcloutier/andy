defmodule Andy.MockRover.ColorSensor do
  @moduledoc "A mock color sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  @max_light 100

  def new(port) do
    %Device{mod: __MODULE__, class: :sensor, port: port, path: "/mock/color_sensor", type: :color, mock: true}
  end

  # Sensing

  def senses(_) do
    [:color, :ambient, :reflected]
  end

  def read(sensor, sense) do
    # TODO - get ready from andy_world
    case sense do
      :color -> color(sensor)
      :ambient -> ambient_light(sensor)
      :reflected -> reflected_light(sensor)
    end
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  def color(sensor) do
    value =
      case :rand.uniform(8) - 1 do
        0 -> :unknown
        1 -> :black
        2 -> :blue
        3 -> :green
        4 -> :yellow
        5 -> :red
        6 -> :white
        7 -> :brown
      end

    {value, sensor}
  end

  def ambient_light(sensor) do
    light(sensor)
  end

  def reflected_light(sensor) do
    light(sensor)
  end

  defp light(sensor) do
    value = Enum.random(0..@max_light)
    {value, sensor}
  end
end
