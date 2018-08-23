defmodule Andy.MockRover.ColorSensor do
	@moduledoc "A mock color sensor"

	@behaviour Andy.Sensing

	alias Andy.Device

	@max_light 100
  @nudge_light 10
	
	def new() do
		%Device{mod: __MODULE__,
						class: :sensor,
						path: "/mock/color_sensor", 
						type: :color,
            mock: true  }
	end

	# Sensing

	def senses(_) do
		[:color, :ambient, :reflected]
	end

	def read(sensor, sense) do
		case sense do
			:color -> color(sensor)
			:ambient -> ambient_light(sensor)
			:reflected -> reflected_light(sensor)
		end
	end

	def nudge(_sensor, sense, value, previous_value) do
		case sense do
			:color -> nudge_color(value, previous_value)
			:ambient -> nudge_ambient_light(value, previous_value)
			:reflected -> nudge_reflected_light(value, previous_value)
		end
	end

	def sensitivity(_sensor, _sense) do
		nil
	end

	### Private

	def color(sensor) do
		value = case :rand.uniform(8) - 1 do
							0 -> nil
							1 -> :black
							2 -> :blue
							3 -> :green
							4 -> :yellow
							5 -> :red
							6 -> :white
							7 -> :brown
						end
		{value, sensor}
	end

  def nudge_color(value, previous_value) do
    if previous_value == nil or :rand.uniform(10) == 1 do
      value
    else
      previous_value
    end 
  end

	def ambient_light(sensor) do
    light(sensor)
	end

  def nudge_ambient_light(value, previous_value) do
    nudge_light(value, previous_value)
  end
  
	def reflected_light(sensor) do
    light(sensor)
	end

  def nudge_reflected_light(value, previous_value) do
    nudge_light(value, previous_value)
  end

  defp light(sensor) do
    value = Enum.random(0..@max_light)
    {value, sensor}
  end

  defp nudge_light(value, previous_value) do
    case previous_value do
      nil ->
        Enum.random(0..@max_light)
      _ ->
        direction = if value - previous_value >= 0, do: 1, else: -1
        nudge = Enum.random(0..@nudge_light)
        previous_value + direction * nudge
        |> max(0)
        |> min(@max_light)
    end

  end

end
