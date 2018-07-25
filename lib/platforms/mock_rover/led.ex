defmodule Andy.MockRover.LED do
	@moduledoc "A mock led"

	alias Andy.Device
	require Logger

	def new(color, position) do
		%Device{mod: __MODULE__,
						class: :led,
						path: "/mock/led/#{position}:#{color}",
						type: "#{position}:#{color}",
						props: %{color: color, position: position, brightness: 0},
            mock: true}
	end

		@doc "Get left vs right position of the LED"
	def position(led) do
		led.props.position
	end

	@doc "Get the color of the LED"
	def color(led) do
		led.props.color
	end

	def max_brightness(_led) do
		255
	end

	def brightness(led) do
		led.props.brightness
	end

	def set_brightness(led, value) do
		Logger.info("Brightness of #{led.path} set to #{value}")
		%Device{led | props: %{led.props | brightness: value}}
	end

end
