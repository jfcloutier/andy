defmodule Andy.ActuatorConfig do
  @moduledoc "An actuator's configuration"

  defstruct name: nil, type: nil, specs: nil, activations: nil, intents: nil

  @doc "Make a new actuator conf"
  def new(name: name, type: type, specs: specs, activations: activations) do
    config = %Andy.ActuatorConfig{name: name, type: type, specs: specs, activations: activations}
    %Andy.ActuatorConfig{config | intents: intent_names(config.activations)}
  end

  defp intent_names(activations) do
    set =
      Enum.reduce(
        activations,
        MapSet.new(),
        fn activation, acc -> MapSet.put(acc, activation.intent) end
      )

    Enum.to_list(set)
  end
end
