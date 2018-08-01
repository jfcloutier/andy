defmodule Andy.Rover.Actuation do
	@moduledoc "Provides the configurations of all rover actuators to be activated"

	require Logger

	alias Andy.{ActuatorConfig, MotorSpec, LEDSpec, SoundSpec, CommSpec, Activation, Script}
  import Andy.Utils
	
	@doc "Give the configurations of all Rover actuators"
  def actuator_configs() do
		[
			ActuatorConfig.new(name: :locomotion,
												 type: :motor,
												 specs: [  # to find and name motors from specs
													 %MotorSpec{name: :left_wheel, port: "outA"},
													 %MotorSpec{name: :right_wheel, port: "outB"}
												 ],
												 activations: [ # scripted actions to be taken upon receiving intents
													 %Activation{intent: :go_forward,
																			 script: going_forward()},
													 %Activation{intent: :go_backward,
																			 script: going_backward()},
													 %Activation{intent: :turn_right,
																			 script: turning_right()},
													 %Activation{intent: :turn_left,
																			 script: turning_left()},
													 %Activation{intent: :stop,
																			 script: stopping()}
												 ]),
			ActuatorConfig.new(name: :manipulation,
												 type: :motor,
												 specs: [
													 %MotorSpec{name: :mouth, port: "outC"}
												 ],
												 activations: [
													 %Activation{intent: :eat,
																			 script: eating()}
												 ]),
			ActuatorConfig.new(name: :leds,
												 type: :led,
												 specs: [
													 %LEDSpec{name: :lr, position: :left, color: :red}, 
													 %LEDSpec{name: :lg, position: :left, color: :green},
													 %LEDSpec{name: :rr, position: :right, color: :red}, 
													 %LEDSpec{name: :rg, position: :right, color: :green}, 
												 ],
												 activations: [
													 %Activation{intent: :green_lights,
																			 script: green_lights()},
													 %Activation{intent: :red_lights,
																			 script: red_lights()},
													 %Activation{intent: :orange_lights,
																			 script: orange_lights()}
												 ]),
      ActuatorConfig.new(name: :sounds,
                         type: :sound,
                         specs: [
                           %SoundSpec{name: :loud_speech, type: :speech, props: %{volume: :loud, speed: :normal, voice: get_voice()}}
                         ],
                         activations: [
                           %Activation{intent: :say_hungry,
                                       script: say_hungry()},
                           %Activation{intent: :say_full,
                                       script: say_full()},
                           %Activation{intent: :say_tracking,
                                       script: say_tracking()},
                           %Activation{intent: :say_scared,
                                       script: say_scared()},
                           %Activation{intent: :say_ok_now,
                                       script: say_ok_now()},
                           %Activation{intent: :say_curious,
                                       script: say_curious()},
                           %Activation{intent: :say_uh_oh,
                                       script: say_uh_oh()},
                           %Activation{intent: :say_stuck,
                                       script: say_stuck()},
                           %Activation{intent: :say_food,
                                       script: say_food()},
                           %Activation{intent: :say_food_nearby,
                                       script: say_food_nearby()},
                           %Activation{intent: :eating_noises,
                                       script: eating_noises()},
                           %Activation{intent: :say,
                                       script: say()}
                         ]),
      ActuatorConfig.new(name: :communicators,
												 type: :comm,
												 specs: [
													 %CommSpec{name: :local, type: :pg2},
													 %CommSpec{name: :remote, type: :rest}
												 ],
												 activations: [
													 %Activation{intent: :broadcast, # intent value = %{info: info}
																			 script: broadcast()},
													 %Activation{intent: :report, 
																			 script: report()}  # intent value = %{info: info}
												 ])													 
		]
	end

	# locomotion

	defp going_forward() do
		fn(intent, motors) ->
			rps_speed = speed(intent.value.speed)
			how_long = round(intent.value.time * 1000)
			Script.new(:going_forward, motors)
			|> Script.add_step(:right_wheel, :set_speed, [:rps, rps_speed])
			|> Script.add_step(:left_wheel, :set_speed, [:rps, rps_speed])
			|> Script.add_step(:all, :run_for, [how_long] )
			#			|> Script.add_wait(how_long)
		end
	end

	defp speed(kind) do
		case kind do
			:very_fast -> very_fast_rps()
			:fast -> fast_rps()
      :normal -> normal_rps()
			:slow -> slow_rps()
			:very_slow -> very_slow_rps()
		end
	end

	defp going_backward() do
		fn(intent, motors) ->
			rps_speed = speed(intent.value.speed)
			how_long = round(intent.value.time * 1000)
			Script.new(:going_backward, motors)
			|> Script.add_step(:right_wheel, :set_speed, [:rps, rps_speed * -1])
			|> Script.add_step(:left_wheel, :set_speed, [:rps, rps_speed * -1])
			|> Script.add_step(:all, :run_for, [how_long])
		end
	end

	defp turning_right() do
		fn(intent, motors) ->
			how_long = round(intent.value * 1000)
			Script.new(:turning_right, motors)
			|> Script.add_step(:left_wheel, :set_speed, [:rps, 0.5])
			|> Script.add_step(:right_wheel, :set_speed, [:rps, -0.5])
			|> Script.add_step(:all, :run_for, [how_long])
		end
  end

	defp turning_left() do
		fn(intent, motors) ->
			how_long = round(intent.value * 1000)
			Script.new(:turning_left, motors)
			|> Script.add_step(:right_wheel, :set_speed, [:rps, 0.5])
			|> Script.add_step(:left_wheel, :set_speed, [:rps, -0.5])
			|> Script.add_step(:all, :run_for, [how_long])
		end
  end

	defp stopping() do
		fn(_intent, motors) ->
			Script.new(:stopping, motors)
			|> Script.add_step(:all, :coast)
			|> Script.add_step(:all, :reset)
		end
  end

	# manipulation

	defp eating() do
		fn(_intent, motors) ->
			Script.new(:eating, motors)
			|> Script.add_step(:mouth, :set_speed, [:rps, 1])
			|> Script.add_step(:mouth, :run_for, [1000])
		end
	end

	# light
  
	defp green_lights() do
		fn(intent, leds) ->
			value = case intent.value do
								:on -> 255
								:off -> 0
							end
			Script.new(:green_lights, leds)
			|> Script.add_step(:lr, :set_brightness, [0])
			|> Script.add_step(:rr, :set_brightness, [0])
			|> Script.add_step(:lg, :set_brightness, [value])
			|> Script.add_step(:rg, :set_brightness, [value])
    end
	end
	
	defp red_lights() do
		fn(intent, leds) ->
			value = case intent.value do
								:on -> 255
								:off -> 0
							end
			Script.new(:red_lights, leds)
			|> Script.add_step(:lg, :set_brightness, [0])
			|> Script.add_step(:rg, :set_brightness, [0])
			|> Script.add_step(:lr, :set_brightness, [value])
			|> Script.add_step(:rr, :set_brightness, [value])
		end
	end
	
	defp orange_lights() do
		fn(intent, leds) ->
			value = case intent.value do
								:on -> 255
								:off -> 0
							end
			Script.new(:orange_lights, leds)
			|> Script.add_step(:all, :set_brightness, [value])
		end
	end

	# Sounds

  defp say_hungry() do
    fn(_intent, sound_players) ->
      Script.new(:say_hungry, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["I am hungry"])
    end
  end
  
  defp say_full() do
    fn(_intent, sound_players) ->
      Script.new(:say_full, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["I am full"])
    end
  end
  
  defp say_tracking() do
    fn(_intent, sound_players) ->
      Script.new(:say_tracking, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["It's mine. Mine. Mine."])
    end
  end
  
  defp say_scared() do
    fn(_intent, sound_players) ->
      Script.new(:say_scared, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["I am scared"])
    end
  end
  
  defp say_ok_now() do
    fn(_intent, sound_players) ->
      Script.new(:say_ok_now, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["I am ok"])
    end
  end
  
  defp say_curious() do
    fn(_intent, sound_players) ->
      Script.new(:say_curious, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Let's check things out"])
    end
  end
  
  defp say_uh_oh() do
    fn(_intent, sound_players) ->
      Script.new(:say_uh_oh, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Uh oh!"])
    end
  end
  
  defp say_stuck() do
    fn(_intent, sound_players) ->
      Script.new(:say_stuck, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["I am stuck"])
    end
  end
  
  defp say_food_nearby() do
    fn(_intent, sound_players) ->
      Script.new(:say_food_near_by, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Smells good!"])
    end
  end
  
  defp say_food() do
    fn(_intent, sound_players) ->
      Script.new(:say_food, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Food! I found food!"])
    end
  end
  
  defp say() do
    fn(intent, sound_players) ->
      Script.new(:say, sound_players)
      |> Script.add_step(:loud_speech, :speak, [intent.value])
    end
  end
  
  defp eating_noises() do
    fn(_intent, sound_players) ->
      Script.new(:say_eating, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Nom de nom de nom"])
    end
  end

	# communications
	
	defp broadcast() do
		fn(intent, communicators) ->
			Script.new(:broadcast, communicators)
			|> Script.add_step(:local, :broadcast, [intent.value])
		end
	end
  
	defp report() do
		fn(intent, communicators) ->
			url = Andy.parent_url()
			Script.new(:report, communicators)
			|> Script.add_step(:remote, :send_percept, [url, :report, intent.value])
		end
	end

end
