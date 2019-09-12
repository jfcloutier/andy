defmodule Andy.MockRover.IRSeekerSensor do
  @moduledoc "A mock infrared seeker sensor"

  @behaviour Andy.Sensing

  alias Andy.Device

  @max_direction 120
  @nudge_direction 30
  @max_proximity 9
  @nudge_proximity 1

  def new() do
    %Device{
      mod: __MODULE__,
      class: :sensor,
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
    direction(sensor)
  end

  def read(sensor, sense) when sense in [:proximity, :proximity_mod] do
    proximity(sensor)
  end

  def nudge(_sensor, sense, value, previous_value) when sense in [:direction, :direction_mod] do
    if previous_value == nil do
      double_max_direction = 2 * @max_direction
      120 - Enum.random(0..double_max_direction)
    else
      direction = if value - previous_value >= 0, do: 1, else: -1
      nudge = Enum.random(0..@nudge_direction)

      (previous_value + direction * nudge)
      |> max(-@max_direction)
      |> min(@max_direction)
    end
  end

  def nudge(_sensor, sense, value, previous_value) when sense in [:proximity, :proximity_mod] do
    if previous_value == nil do
      Enum.random(0..@max_proximity)
    else
      direction = if value - previous_value >= 0, do: 1, else: -1
      nudge = Enum.random(0..@nudge_proximity)

      (previous_value + direction * nudge)
      |> max(0)
      |> min(@max_proximity)
    end
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
