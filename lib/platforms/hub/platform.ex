defmodule Andy.Hub.Platform do
	@moduledoc "The Hub platform"

	@behaviour Andy.PlatformBehaviour

	alias Andy.{SoundPlayer, Device, Hub}
	require Logger

	### PlatformBehaviour

	def start() do
		Logger.info("Platform hub started")
	end

	def ready?() do
		true
	end

	def ports_config() do
		[]
  end

	def display(words) do
		Logger.info("DISPLAYING: #{words}")
	end

	def actuation_logic() do
		Hub.Actuation.actuator_configs()
	end

	def voice() do
		"en-us+f1"
	end

	def sound_players() do
		[SoundPlayer.new()]
	end

	# Everything else is N/A
	
	def mode(_device_type) do
		"hub"
  end
  
  def device_code(_device_type) do
		nil
  end

	def device_manager(_type) do
		__MODULE__ 
	end

	def sensors() do
		[]
	end

	def motors() do
		[]
	end

	def lights() do
		[]
	end

	def shutdown() do
		:ok # Do nothing
	end

	def sensor_read_sense(_device, _sense) do
		nil
	end

	def motor_read_sense(_device, _sense) do
		nil
	end

	def sensor_sensitivity(_device, _sense) do
		0
	end
	
	def motor_sensitivity(_device, _sense) do
		0
	end

	def senses_for_id_channel(_channel) do
		[]
	end

	def nudge(_device, _sense, _value, _previous_value) do 
	  nil
	end

	def execute_command(%Device{mod: mod} = device, command, params) do
		apply(mod, command, [device | params])
	end
	
end
