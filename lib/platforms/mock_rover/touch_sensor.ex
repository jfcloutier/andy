defmodule Andy.MockRover.TouchSensor do
	@moduledoc "A mock touch sensor"

	@behaviour Andy.Sensing

	alias Andy.Device
	
	def new() do
		%Device{mod: __MODULE__,
						class: :sensor,
						path: "/mock/touch_sensor", 
						type: :touch,
            mock: true}
	end

	### Sensing
	
	def senses(_) do
		[:touch]
	end

	def read(sensor, _sense) do
		value = case :rand.uniform(2) - 1 do
			0 -> :released
			1 -> :pressed
    end
		{value, sensor}
	end

	def nudge(_sensor, _sense, value, previous_value) do
		case previous_value do
      nil -> value
      _ ->
        if :rand.uniform(20) == 1 do
          value
        else
          previous_value
        end
    end
	end
	
	def sensitivity(_sensor, _sense) do
	  nil
	end

end
