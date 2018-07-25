defmodule Andy.Rover.Platform do

	@behaviour Andy.PlatformBehaviour

	@moduledoc "Module implementing smart thing platform_dispatch calls"

	alias Andy.Ev3.{Brick, Display, LegoSound, LegoSensor, LegoMotor, LegoLED, InfraredSensor}
	require Logger
	
	### PlatformBehaviour

	def start() do
		Logger.info("Starting ev3 system")
		Brick.start()
	end

	def ready?() do
		Brick.ready?()
	end

	def display(words) do
		Display.show_banner(words)
	end

	def actuation_logic() do
		Andy.Rover.Actuation.actuator_configs()
	end
	
	def mode(device_type) do
    case device_type do
      :infrared -> "ev3-uart"
      :touch -> "ev3-analog"
      :gyro -> "ev3-uart"
      :color -> "ev3-uart"
      :ultrasonic -> "ev3-uart"
      :large -> "tacho-motor"
      :medium -> "tacho-motor"
    end
  end
  
  def device_code(device_type) do
    case device_type do
      :infrared -> "lego-ev3-ir"
      :touch -> "lego-ev3-touch"
      :gyro -> "lego-ev3-gyro"
      :color -> "lego-ev3-color"
      :ultrasonic -> "lego-ev3-us"
      :large -> "lego-ev3-l-motor"
      :medium -> "lego-ev3-m-motor"
    end
  end

	def device_manager(type) do
		case type do
			:motor -> LegoMotor
			:sensor -> LegoSensor
			:led -> LegoLED
			:sound -> LegoSound
		end
	end

	def sensors() do
		LegoSensor.sensors()
	end

	def motors() do
		LegoMotor.motors()
	end

	def sound_players() do
		LegoSound.sound_players()
	end

	def lights() do
		LegoLED.leds()
	end

	def shutdown() do
		System.cmd("poweroff", [])
	end

	def voice() do
		"en-sc"
	end

	def sensor_read_sense(device, sense) do
		LegoSensor.read(device, sense)
	end

	def motor_read_sense(device, sense) do
		LegoMotor.read(device, sense)
	end

	def sensor_sensitivity(device, sense) do
		LegoSensor.sensitivity(device, sense)
	end
	
	def motor_sensitivity(device, sense) do
		LegoMotor.sensitivity(device, sense)
	end

	def senses_for_id_channel(channel) do
		InfraredSensor.beacon_senses_for(channel)
	end

	def nudge(_device, _sense, value, _previous_value) do
		value
	end
		
	###

end
