defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger

  defmodule State do
      defstruct definition: nil, # a GenerativeModelDef
                perception: nil, # current percepts received from sub-gms and generated from beliefs
                beliefs: nil, # current beliefs in GM conjectures - conjecture_name => Belief
                attention: %{} # attention given to sub-GMs - sub-gm_def_name => float
  end

  defmodule Perception do
    defstruct received: %{}, # received percepts for current round - sub-gm_def_name => [Percept,...]
              generated: %{} # generated percepts for current round - conjecture_name => Percept
  end

  defmodule Belief do
    defstruct level: 0,
              conjecture_name: nil,
              parameters: %{} # conjecture_parameter_name => value obtained from supporting Percept
  end

  @doc "Child spec as supervised worker"
  def child_spec(generative_mode_def) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the memory server"
  def start_link(generative_model_def) do
    name = generative_model_def.name
    Logger.info("Starting Generative Model #{name}")
    Agent.start_link(
      fn () ->
        %State{definition: generative_model_def,
               perception: %Perception{},
               beliefs: initial_beliefs(generative_model_def)
        }
      end,
      [name: name]
    )
  end

  defp initial_beliefs(generative_model_def) do
    # TODO
    %{}
  end

end