defmodule Andy.MockRover.InfraredSensor do
	@moduledoc "A mock infrared sensor"

	@behaviour Andy.Sensing

	alias Andy.Device
	import Andy.Utils

	def new() do
		%Device{mod: __MODULE__,
						class: :sensor,
						path: "/mock/infrared_sensor", 
						type: :infrared,
						mock: true}
	end

	### Sensing
	
	def senses(_) do
		beacon_senses = Enum.reduce(1 .. max_beacon_channels(),
																[],
			fn(channel, acc) ->
				acc ++
					[{:beacon_heading, channel},
					 {:beacon_distance, channel},
					 {:beacon_on, channel},
					 {:remote_buttons, channel}]
			end)
		[:proximity | beacon_senses]
	end

	def beacon_senses_for(channel) do
		[{:beacon_heading, channel}, {:beacon_distance, channel}, {:beacon_on, channel}]
	end


	def read(sensor, :proximity) do
		proximity(sensor)			
	end

	def read(sensor, {:remote_buttons, channel}) do
		remote_buttons(sensor, channel)
	end

	def read(sensor, {beacon_sense, channel}) do
		case beacon_sense do
			:beacon_heading -> seek_heading(sensor, channel)
			:beacon_distance -> seek_distance(sensor, channel)
			:beacon_on -> seek_beacon_on?(sensor, channel)
		end
	end
	
	def nudge(_sensor, {beacon_sense, channel}, value, previous_value) do
		case beacon_sense do
			:beacon_heading -> nudge_heading(channel, value, previous_value)
			:beacon_distance -> nudge_distance(channel, value, previous_value)
			:beacon_on -> nudge_beacon_on?(channel, value, previous_value)
		end
	end
	
	def sensitivity(_sensor, _sense) do
		nil
	end

	### Private

	defp proximity(sensor) do
		value = :rand.uniform(20)
		{value, sensor}
	end

	defp seek_heading(sensor, _channel) do
		value = 5 - :rand.uniform(10)
    {value, sensor}
	end

  defp nudge_heading(_channel, value, previous_value) do
    if previous_value == nil or :rand.uniform(10) == 1 do
      25 - :rand.uniform(50)
    else
      value + previous_value |> max(-25) |> min(25)
    end
  end

	defp seek_distance(sensor, _channel) do
		value = :rand.uniform(10) - 7
    {value, sensor}
	end

  defp nudge_distance(_channel, value, previous_value) do
    case previous_value do
      nil -> 50 + :rand.uniform(50)
      _ -> value + previous_value |> max(0) |> min(100)
    end
  end

	defp seek_beacon_on?(sensor, _channel) do
		value = :rand.uniform(2) == 2
		{value, sensor}
	end

  defp nudge_beacon_on?(_channel, value, previous_value) do
    case previous_value do
      nil -> value
      _ ->
        if :rand.uniform(4) == 4 do
          value
        else
          previous_value
        end
    end
  end

	defp remote_buttons(sensor, _channel) do
		value = case :rand.uniform(12) - 1 do
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
			_ -> %{red: nil, blue: nil} # 0 or 9
		end
		{value, sensor}
	end
	
end
