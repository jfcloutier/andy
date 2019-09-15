defmodule Andy.BrickPi.InfraredSensor do
  @moduledoc """
  Infrared sensor to detect a beacon on any of channels 1-4.
  :proximity - 0 to 70 cm, or :unknown
  {:beacon_distance, channel} -  distance is 0 to 70 cm, or :unknown
  {:beacon_heading, channel} - -25 (far left) to 25 (far right), 0 is either straight ahead or unknown
  {:beacon_on, channel} - true or false
  {:remote_button, channel} - %{red: status, blue: status} where status is one of nil, :up, :down, :up_down
  """

  @behaviour Andy.Sensing

  import Andy.Utils
  import Andy.BrickPi.Sysfs
  alias Andy.BrickPi.LegoSensor
  require Logger

  @proximity "IR-PROX"
  @seek "IR-SEEK"
  @remote "IR-REMOTE"

  ### Sensing behaviour

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

  def pause(_) do
    500
  end

  def sensitivity(_sensor, sense) do
    case sense do
      :beacon_proximity -> 2
      {:beacon_heading, _} -> 2
      {:beacon_distance, _} -> 2
      {:beacon_on, _} -> nil
      {:remote_buttons, _} -> nil
    end
  end

  ####

  @doc "Get proximity as a percent - 70+cm ~> 100, 0cm ~> 1"
  def beacon_proximity(sensor) do
    updated_sensor = set_proximity_mode(sensor)

    value =
      case get_attribute(updated_sensor, "value0", :integer) do
        100 -> :unknown
        percent -> round(percent / 100 * 70)
      end

    {value, updated_sensor}
  end

  @doc "Get beacon heading on a channel (-25 for far left, 25 for far right => :unknown, 0 if absent or straight ahead)"
  def seek_heading(sensor, channel) do
    updated_sensor = set_seek_mode(sensor)
    value = get_attribute(updated_sensor, "value#{(channel - 1) * 2}", :integer)
    {value, updated_sensor}
  end

  @doc "Get beacon distance on a channel (as percentage - 0 means immediate proximity, 100 means 70cm, -128 means unknown)"
  def seek_distance(sensor, channel) do
    updated_sensor = set_seek_mode(sensor)
    raw = get_attribute(updated_sensor, "value#{(channel - 1) * 2 + 1}", :integer)
    value = if raw == -128, do: :unknown, else: round(raw / 100 * 70)
    {value, updated_sensor}
  end

  @doc "Is the beacon on in seek mode?"
  def seek_beacon_on?(sensor, channel) do
    {distance, sensor1} = seek_distance(sensor, channel)
    {heading, sensor2} = seek_heading(sensor1, channel)
    {not (distance == -128 && heading == 0), sensor2}
  end

  @doc "Get remote button pushed (maximum two buttons) on a channel. 
  (E.g. %{red: :up, blue: :down}, or %{red: :up_down, blue: nil}"
  def remote_buttons(sensor, channel) do
    updated_sensor = set_remote_mode(sensor)
    val = get_attribute(updated_sensor, "value#{channel - 1}", :integer)

    value =
      case val do
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

    {value, updated_sensor}
  end

  @doc "Are one or more remote button pushed on a given channel?"
  def remote_pushed?(sensor, channel) do
    {%{red: red, blue: blue}, updated_sensor} = remote_buttons(sensor, channel)
    {red != nil || blue != nil, updated_sensor}
  end

  @doc "Is the beacon turned on on a given channel in remote mode?"
  def remote_beacon_on?(sensor, channel) do
    updated_sensor = set_remote_mode(sensor)
    value = get_attribute(updated_sensor, "value#{channel - 1}", :integer) == 9
    {value, updated_sensor}
  end

  ### PRIVATE

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
    beacon_proximity(sensor)
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

  defp set_proximity_mode(sensor) do
    LegoSensor.set_mode(sensor, @proximity)
  end

  defp set_seek_mode(sensor) do
    LegoSensor.set_mode(sensor, @seek)
  end

  defp set_remote_mode(sensor) do
    LegoSensor.set_mode(sensor, @remote)
  end
end
