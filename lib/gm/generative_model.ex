defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger
  @forget_after 10_000 # for how long perception is retained

  defmodule State do
      defstruct definition: nil, # a GenerativeModelDef
                perception: [], # current beliefs received from sub-gms
                beliefs: %{}, # current beliefs in GM conjectures - conjecture_name => Belief
                attention: %{}, # attention given to sub-GMs - sub-gm_def_name => float
                round_timer: nil # pid of round timer
  end

  defmodule Perception do
    defstruct round_timestamp: nil, # timestamp for the round
              received_beliefs: %{} # sub_gm_name => [belief, ...]
  end

  @doc "Child spec as supervised worker"
  def child_spec(generative_model_def) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [generative_model_def] }
    }
  end

  @doc "Start the memory server"
  def start_link(generative_model_def) do
    name = generative_model_def.name
    Logger.info("Starting Generative Model #{name}")
    Agent.start_link(
      fn () ->
        %State{definition: generative_model_def,
               beliefs: initial_beliefs(generative_model_def),
               round_timer: spawn_link(fn -> complete_round(generative_model_def) end)
        }
      end,
      [name: name]
    )
  end

  # Forget all expired percepts every second
  defp complete_round(generative_model_def) do
    :timer.sleep(generative_model_def.max_round_duration)
    Logger.info("Completing round for GM #{generative_model_def.name}")
    :ok = Agent.update(generative_model_def.name, fn(state) -> execute_round(state) end)
    complete_round(generative_model_def)
  end

  defp initial_beliefs(_generative_model_def) do
    # TODO
    %{}
  end

  defp execute_round(state) do
    # TODO
    state
  end

end