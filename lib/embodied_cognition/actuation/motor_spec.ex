defmodule Andy.MotorSpec do
	@moduledoc "Struct for motor specifications"

  # properties name and props are required to be a *Spec
	defstruct name: nil, port: nil, props: %{}

	@doc "Does a motor match a motor spec?"
	def matches?(motor_spec, device) do
		device.class == :motor and motor_spec.port == Andy.translate_port(device.port)
	end
	
end
