defmodule Andy.BrickPi.InfraredSensor do
	@moduledoc "Infrared sensor"
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

	def read(sensor, sense) do
		{_, updated_sensor} = do_read(sensor, sense)
		do_read(updated_sensor, sense) # double read seems necessary after a mode change
	end

	defp do_read(sensor, :proximity) do
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

	def pause(_) do
	 500
	end

	def sensitivity(_sensor, sense) do
		case (sense) do
			:proximity -> 2
			{:beacon_heading, _} -> 2
			{:beacon_distance, _} -> 2
			{:beacon_on, _} -> nil
			{:remote_buttons, _} -> nil
		end
	end

  ####
	
@doc "Get proximity as a percent - 70+cm ~> 100, 0cm ~> 1"
  def proximity(sensor) do
		updated_sensor = set_proximity_mode(sensor)
		value = get_attribute(updated_sensor, "value0", :integer)
		{value, updated_sensor}
  end

	@doc "Get beacon heading on a channel (-25 for far left, 25 for far right, 0 if absent or straight ahead)"
  def seek_heading(sensor, channel)  do 
	updated_sensor = set_seek_mode(sensor)
	value = get_attribute(updated_sensor, "value#{(channel - 1) * 2}", :integer)
	{value, updated_sensor}
  end

	@doc "Get beacon distance on a channel (as percentage - 0 means immediate proximity, 100 means outside of range)"
  def seek_distance(sensor, channel) do
		updated_sensor = set_seek_mode(sensor)
		value = get_attribute(updated_sensor, "value#{((channel - 1) * 2) + 1}", :integer)
		{min(100, abs(value)), updated_sensor}
  end

  @doc "Is the beacon on in seek mode?"
	def seek_beacon_on?(sensor, channel) do
		{distance, sensor1} = seek_distance(sensor, channel)
		{heading, sensor2} =  seek_heading(sensor1, channel)
		{not(distance == -128 && heading == 0), sensor2}
  end

	@doc "Get remote button pushed (maximum two buttons) on a channel. 
  (E.g. %{red: :up, blue: :down}, or %{red: :up_down, blue: nil}"
  def remote_buttons(sensor, channel) do
		updated_sensor = set_remote_mode(sensor)
		val = get_attribute(updated_sensor, "value#{channel - 1}", :integer)
		value = case val do
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
