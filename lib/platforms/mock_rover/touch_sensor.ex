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
		random = Enum.random(0..10)
		value = cond do
			random > 0 -> :released
			true -> :pressed
    end
		{value, sensor}
	end

	def nudge(_sensor, _sense, value, previous_value) do
		case previous_value do
      nil -> value
      _ ->
        if Enum.random(0..10) == 0 do
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
