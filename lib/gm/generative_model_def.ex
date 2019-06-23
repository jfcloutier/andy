defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model"

  @default_max_round_duration 500 # half a second

  alias Andy.GM.Belief

  defstruct name: nil,
              # the unique name of a generative model
            conjectures: [],
              # GM conjectures
            contradictions: [],
              # sets of mutually-exclusive conjectures (by name) - hyper-prior
            priors: %{},
              # conjecture_name => %{} parameter values of initially believed conjectures
            max_round_duration: @default_max_round_duration # the maximum duration of a round for the GM

  # level: 0, # from 0 to 1, how much the GM believes its named conjecture
  #            generative_model_name: nil,
  #            conjecture_name: nil,
  #            parameter_values: %{}
  def initial_beliefs(gm_def) do
    prior_conjecture_names = Map.keys(gm_def.priors)
    Enum.reduce(
      gm_def.priors,
      [],
      fn (conjecture_name, acc) ->
        parameter_values = Map.get(gm_def.priors, conjecture_name)
        %Belief{
          level: 1,
          source: {:gm, gm_def.name},
          about: conjecture_name,
          parameter_values: parameter_values
        }
      end
    )
  end
end