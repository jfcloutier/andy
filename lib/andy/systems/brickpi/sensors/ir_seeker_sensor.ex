defmodule Andy.BrickPi.IRSeekerSensor do
  @moduledoc """
    Infrared seeker sensor.
    Direction is :unknown or -120, -90, -60, -30, 0, 30, 60, 90, 120 degrees
    Proximity is :unknown or 0..9, with 9 being closest
  """
  @behaviour Andy.Sensing

  import Andy.BrickPi.Sysfs
  alias Andy.BrickPi.LegoSensor
  require Logger

  @direction_unmodulated "DC-ALL"
  @direction_modulated "AC-ALL"

  ### Sensing behaviour

  def senses(_) do
    [:direction, :direction_mod, :proximity, :proximity_mod]
  end

  def read(sensor, sense) do
    {_, updated_sensor} = do_read(sensor, sense)
    # double read seems necessary after a mode change
    do_read(updated_sensor, sense)
  end

  def pause(_) do
    500
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  #### PRIVATE

  defp do_read(sensor, sense) do
    updated_sensor = set_mode(sensor, sense)
    dir_value = get_attribute(updated_sensor, "value0", :integer)

    cond do
      sense in [:direction, :direction_mod] ->
        angle =
          cond do
            dir_value == 0 ->
              :unknown

            dir_value < 5 ->
              (5 - dir_value) * -30

            dir_value == 5 ->
              0

            dir_value > 5 ->
              (dir_value - 5) * 30
          end

        {angle, updated_sensor}

      sense in [:proximity, :proximity_mode] ->
        if dir_value == 0 do
          {:unknown, updated_sensor}
          # Direction	Strength Source
          # 1	Channel 1
          # 2	Channel 1 and 2
          # 3	Channel 2
          # 4	Channel 2 and 3
          # 5	Channel 3
          # 6	Channel 3 and 4
          # 7	Channel 4
          # 8	Channel 4 and 5
          # 9	Channel 5
        else
          signal_strength =
            if dir_value in [1, 3, 5, 7, 9] do
              index = Enum.find_index([1, 3, 5, 7, 9], fn x -> x == dir_value end)
              get_attribute(updated_sensor, "value#{index}", :integer)
            else
              index = Enum.find_index([2, 4, 6, 8], fn x -> x == dir_value end)
              val1 = get_attribute(updated_sensor, "value#{index}", :integer)
              val2 = get_attribute(updated_sensor, "value#{index + 1}", :integer)
              round((val1 + val2) / 2)
            end

          {signal_strength, updated_sensor}
        end
    end
  end

  defp set_mode(sensor, sense) when sense in [:direction, :proximity] do
    LegoSensor.set_mode(sensor, @direction_unmodulated)
  end

  defp set_mode(sensor, sense) when sense in [:direction_mod, :proximity_mod] do
    LegoSensor.set_mode(sensor, @direction_modulated)
  end
end
