defmodule Andy.Hub.Actuation do
	@moduledoc "Provides the configurations for hub actuators"

	require Logger

	alias Andy.{ActuatorConfig, SoundSpec, CommSpec, Activation, Script, Intent}
  import Andy.Utils

	@doc "Give the configurations of all actuators to be activated"
  def actuator_configs() do
		[
      ActuatorConfig.new(name: :sounds,
                         type: :sound,
                         specs: [
                           %SoundSpec{name: :loud_speech, type: :speech, props: %{volume: :loud, speed: :normal, voice: get_voice()}}
                         ],
                         activations: [
                           %Activation{intent: :say_calm_down,
                                       action: say_calm_down()},
                           %Activation{intent: :say_share_food,
                                       action: say_share_food()},
                           %Activation{intent: :say_parenting,
                                       action: say_parenting()}
                         ]),
      ActuatorConfig.new(name: :communicators,
												 type: :comm,
												 specs: [
													 %CommSpec{name: :local, type: :pg2},
													 %CommSpec{name: :remote, type: :rest}
												 ],
												 activations: [
													 %Activation{intent: :command, 
																			 action: command()}  # intent value = %{command: command, to_url: url}
												 ])													 

		]
	end

  defp say_parenting() do
    fn(_intent, sound_players) ->
      Script.new(:say_parenting, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["It's not easy being a mom!"])
    end
  end

  defp say_calm_down() do
    fn(%Intent{value: %{member_name: member_name}}, sound_players) ->
			name = name_from(member_name)
      Script.new(:say_calm_down, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Calm down little #{name}"])
			|> Script.add_wait(1200)
    end
  end

  defp say_share_food() do
    fn(%Intent{value: %{member_name: member_name}}, sound_players) ->
			name = name_from(member_name)
      Script.new(:say_calm_down, sound_players)
      |> Script.add_step(:loud_speech, :speak, ["Share your food with #{name}!"])
    end
  end

	defp command() do
		fn(intent, communicators) ->
			%{command: command, to_url: url} = intent.value
			Script.new(:command, communicators)
			|> Script.add_step(:remote, :send_percept, [url, :mom_says, %{command: command}])
		end
	end

	defp name_from(member_name) do
		[name | _] = String.splitter(member_name, "@") |> Enum.to_list()
    name
	end
	
end
