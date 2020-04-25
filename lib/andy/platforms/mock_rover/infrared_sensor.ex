defmodule Andy.MockRover.InfraredSensor do
  @moduledoc "A mock infrared sensor"

  @behaviour Andy.Sensing

  alias Andy.Device
  import Andy.Utils
  require Logger

  @max_distance 70
  @max_heading 25

  def new(port) do
    %Device{
      mod: __MODULE__,
      class: :sensor,
      port: port,
      path: "/mock/infrared_sensor",
      type: :infrared,
      mock: true
    }
  end

  ### Sensing

  def senses(_) do
    # TODO - get ready from andy_world
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

  defp seek_distance(sensor, _channel) do
    value = Enum.random(0..@max_distance)
    {value, sensor}
  end

  defp seek_beacon_on?(sensor, _channel) do
    value = :rand.uniform(2) == 2
    {value, sensor}
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
