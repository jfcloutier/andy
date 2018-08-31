defmodule Andy.BrickPi.LegoMotor do
	@moduledoc "Lego motors access"

  alias Andy.Device
	import Andy.BrickPi.Sysfs
	require Logger

	@sys_path "/sys/class/tacho-motor"
  @prefix "motor" 
  @driver_regex ~r/lego-(.+)-motor/i

  @doc "Is this type of device a motor?"
  def motor?(device_type) do
    device_type in [:medium, :large]
  end

	@doc "Generates a list of all plugged in motor devices"
	def motors() do
	 	case File.ls(@sys_path) do
			{:ok, files} -> files
			{:error, reason} ->
				Logger.warn("Failed getting motor files: #{inspect reason}")
				[]
		end
		|> Enum.filter(&(String.starts_with?(&1, @prefix)))
		|> Enum.map(&(init_motor("#{@sys_path}/#{&1}")))
  end

	@doc "Get the list of senses from a motor"
	def senses(motor) do
		apply(module_for(motor), :senses, [motor])
	end


	@doc "Read the value of a sense from a motor"
	def read(motor, sense) do # {value, updated_motor} - value can be nil
		try do
			apply(module_for(motor), :read, [motor, sense])
		rescue
			error ->
				Logger.warn("#{inspect error} when reading #{inspect sense} from #{inspect motor}")
				{nil, motor}
		end
	end

	@doc "Get how long to pause between reading a sense from a motor. In msecs"
	def pause(motor) do
			apply(module_for(motor), :pause, [motor])
	end

	@doc "Get the resolution of a motor (the delta between essentially identical readings). Nil or an integer."
	def sensitivity(motor, sense) do
			apply(module_for(motor), :sensitivity, [motor, sense])
	end

	  @doc "Is this a large motor?"
  def large?(motor) do
		motor.type == :large
  end

  @doc "Is this a medium motor?"
  def medium?(motor) do
		motor.type == :medium
  end

	@doc "Execute a motor command"
	def execute_command(motor, command, params) do
#		Logger.info("--- Executing motor #{motor.path} #{command} #{inspect params}")
		apply(motor.mod, command, [motor | params])
	end

	@doc "Get motor controls"
  def get_sys_controls(motor) do
		%{polarity: get_attribute(motor, "polarity", :atom),
			speed:  get_attribute(motor, "speed_sp", :integer), # in counts/sec,
			duty_cycle:  get_attribute(motor, "duty_cycle_sp", :integer),
			ramp_up: get_attribute(motor, "ramp_up_sp", :integer),
			ramp_down: get_attribute(motor, "ramp_down_sp", :integer),
			position: get_attribute(motor, "position_sp", :integer), # in counts,
	 	  time: get_attribute(motor, "time_sp", :integer)
			}
  end

	### PRIVATE

	defp module_for(motor) do
		module_for_type(motor.type)
	end

	defp module_for_type(_type) do
		Andy.BrickPi.Tachomotor
	end
	
  defp init_motor(path) do
		port_name = read_sys(path, "address")
    driver_name = read_sys(path, "driver_name")
    [_, type_signature] = Regex.run(@driver_regex, driver_name)
    type = case type_signature do
						 "ev3-l" -> :large
						 "ev3-m" -> :medium
						 "nxt" -> :large # or whatever
           end
    motor = %Device{mod: module_for_type(type),
										class: :motor,
										path: path, 
										port: port_name, 
										type: type}
    count_per_rot = get_attribute(motor, "count_per_rot", :integer)
    commands = get_attribute(motor, "commands", :list)
		stop_actions = get_attribute(motor, "stop_actions", :list)
		max_speed = get_attribute(motor, "max_speed", :integer)
    %Device{motor | props: %{count_per_rot: count_per_rot,
														 max_speed: max_speed,
														 commands: commands,
														 stop_actions: stop_actions,
														 controls: Map.put_new(get_sys_controls(motor), 
																									 :speed_mode, 
																									 nil)}}  
  end

end
