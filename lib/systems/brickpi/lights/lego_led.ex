defmodule Andy.BrickPi.LegoLED do
	@moduledoc "BrickPi3 LED access"

	@behaviour Andy.Lighting
	
	require Logger
	import Andy.BrickPi.Sysfs
	alias Andy.Device
	require Logger
	
	@sys_path "/sys/class/leds"
  @brickpi_prefix ~r/^led\d/


  @doc "Get the available LEDs"
	def leds() do
    File.ls!(@sys_path)
    |> Enum.filter(&(Regex.match?(@brickpi_prefix, &1)))
    |> Enum.map(&(init_brickpi_led("#{@sys_path}/#{&1}")))
  end

  @doc "Find a led device by position and color, or nil"
	def led(position: position, color: color) do
		leds()
		|> Enum.find(&(position(&1) == position and color(&1) == color))
	end

	# Lighting

	@doc "Get left vs right position of the LED"
	def position(led) do
		led.props.position
	end

	@doc "Get the color of the LED"
	def color(led) do
		led.props.color
	end

	@doc "Get the LED max brightness"
	def max_brightness(led) do
		get_attribute(led, "max_brightness", :integer)
	end

	@doc "Get the current brightness"
	def brightness(led) do
		get_attribute(led, "brightness", :integer)
	end

	@doc "Set the brightness"
	def set_brightness(led, value) do
		set_attribute(led, "brightness", value)
		led
	end
	
	###
	
	@doc "Execute an LED command"
	def execute_command(led, command, params) do
#		Logger.info("--- Executing LED #{led.path} #{command} #{inspect params}")
		spawn(fn() -> apply(module_for(led), command, [led | params]) end) # call to LEDs seems to be time-consuming
    led
	end

	### PRIVATE

	defp module_for(led) do
		module_for_type(led.type)
	end

	defp module_for_type(_type) do
		Andy.BrickPi.LegoLED
	end

  defp init_brickpi_led(path) do
    led = %Device{class: :led,
      path: path,
      port: nil,
      type: :led # TODO - ok?
		}
     %Device{led | props: %{position: :left, color: :blue}}
  end

end
