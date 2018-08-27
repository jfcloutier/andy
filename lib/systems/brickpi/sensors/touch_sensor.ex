defmodule Andy.BrickPi.TouchSensor do
	@moduledoc "Touch sensor"
	@behaviour Andy.Sensing

  import Andy.BrickPi.Sysfs

	### Sensing behaviour
	
	def senses(_) do
		[:touch]
	end

	def read(sensor, :touch) do
		{state(sensor), sensor}
	end

	def pause(_) do
		500
	end

	def sensitivity(_, _) do
		nil
	end

	####
	
	@doc "Get the state of the touch sensor (:pressed or :released)"
  def state(sensor) do
		case get_attribute(sensor, "value0", :integer) do
			0 -> :released
			1 -> :pressed
    end
  end

	@doc "Is the touch sensor pressed"
  def pressed?(sensor) do
		{state(sensor) == :pressed, sensor}
  end

	@doc "Is the touch sensor released?"
  def released?(sensor) do
		{state(sensor) == :released, sensor}
  end

end
