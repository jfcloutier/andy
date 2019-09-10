defmodule Andy.MockRover.InfraredSensor do
  @moduledoc "A mock infrared sensor"

  @behaviour Andy.Sensing

  alias Andy.Device
  import Andy.Utils
  require Logger

  @max_distance 70
  @nudge_distance 5
  @max_heading 25
  @nudge_heading 5

  def new() do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      path: "/mock/infrared_sensor",
      type: :infrared,
      mock: true
    }
  end

  ### Sensing

  def senses(_) do
    beacon_senses =
      Enum.reduce(
        1..max_beacon_channels(),
        [],
        fn channel, acc ->
          acc ++
            [
              beacon_sense(:beacon_heading, channel),
              beacon_sense(:beacon_distance, channel),
              beacon_sense(:beacon_on, channel),
              beacon_sense(:remote_buttons, channel)
            ]
        end
      )

    [:beacon_proximity | beacon_senses]
  end

  def beacon_senses_for(channel) do
    [
      beacon_sense(:beacon_heading, channel),
      beacon_sense(:beacon_distance, channel),
      beacon_sense(:beacon_on, channel)
    ]
  end

  def read(sensor, sense) do
    expanded_sense = expand_sense(sense)
    {_, updated_sensor} = do_read(sensor, expanded_sense)
    # double read seems necessary after a mode change
    do_read(updated_sensor, expanded_sense)
  end

  def nudge(_sensor, sense, value, previous_value) do
    case expand_sense(sense) do
      {:beacon_heading, channel} -> nudge_heading(channel, value, previous_value)
      {:beacon_distance, channel} -> nudge_distance(channel, value, previous_value)
      {:beacon_on, channel} -> nudge_beacon_on?(channel, value, previous_value)
      :beacon_proximity -> nudge_proximity(value, previous_value)
    end
  end

  def sensitivity(_sensor, _sense) do
    nil
  end

  ### Private

  defp beacon_sense(kind, channel) do
    "#{kind}/#{channel}" |> String.to_atom()
  end

  defp expand_sense(sense) do
    case String.split("#{sense}", "/") do
      [kind] ->
        String.to_atom(kind)

      [kind, channel_s] ->
        {channel, _} = Integer.parse(channel_s)
        {String.to_atom(kind), channel}
    end
  end

  defp do_read(sensor, :beacon_proximity) do
    proximity(sensor)
  end

  defp do_read(sensor, {:remote_buttons, channel}) do
    remote_buttons(sensor, channel)
  end

  defp do_read(sensor, {beacon_sense, channel}) do
    case beacon_sense do
      :beacon_heading -> seek_heading(sensor, channel)
      :beacon_distance -> seek_distance(sensor, channel)
      :beacon_on -> seek_beacon_on?(sensor, channel)
    end
  end

  defp proximity(sensor) do
    value = :rand.uniform(20)
    {value, sensor}
  end

  defp seek_heading(sensor, _channel) do
    double_max_heading = 2 * @max_heading
    value = 25 - Enum.random(0..double_max_heading)
    {value, sensor}
  end

  defp nudge_heading(_channel, value, previous_value) do
    if previous_value == nil do
      double_max_heading = 2 * @max_heading
      25 - Enum.random(0..double_max_heading)
    else
      direction = if value - previous_value >= 0, do: 1, else: -1
      nudge = Enum.random(0..@nudge_heading)

      (previous_value + direction * nudge)
      |> max(-@max_heading)
      |> min(@max_heading)
    end
  end

  defp seek_distance(sensor, _channel) do
    value = Enum.random(0..@max_distance)
    {value, sensor}
  end

  defp nudge_distance(_channel, value, previous_value) do
    case previous_value do
      nil ->
        Enum.random(0..@max_distance)

      _ ->
        direction = if value - previous_value >= 0, do: 1, else: -1
        nudge = Enum.random(0..@nudge_distance)

        (previous_value + direction * nudge)
        |> max(0)
        |> min(@max_distance)
    end
  end

  defp nudge_proximity(value, previous_value) do
    case previous_value do
      nil ->
        Enum.random(0..@max_distance)

      _ ->
        direction = if value - previous_value >= 0, do: 1, else: -1
        nudge = Enum.random(0..@nudge_distance)

        (previous_value + direction * nudge)
        |> max(0)
        |> min(@max_distance)
    end
  end

  defp seek_beacon_on?(sensor, _channel) do
    value = :rand.uniform(2) == 2
    {value, sensor}
  end

  defp nudge_beacon_on?(_channel, value, previous_value) do
    case previous_value do
      nil ->
        value

      _ ->
        if :rand.uniform(4) == 4 do
          value
        else
          previous_value
        end
    end
  end

  defp remote_buttons(sensor, _channel) do
    value =
      case :rand.uniform(12) - 1 do
        1 -> %{red: :up, blue: nil}
        2 -> %{red: :down, blue: nil}
        3 -> %{red: nil, blue: :up}
        4 -> %{red: nil, blue: :down}
        5 -> %{red: :up, blue: :up}
        6 -> %{red: :up, blue: :down}
        7 -> %{red: :down, blue: :up}
        8 -> %{red: :down, blue: :down}
        10 -> %{red: :up_down, blue: nil}
        11 -> %{red: nil, blue: :up_down}
        # 0 or 9
        _ -> %{red: nil, blue: nil}
      end

    {value, sensor}
  end
end
