defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model's definition"

  @default_max_round_duration 500 # half a second

  alias Andy.GM.Belief

  defstruct name: nil,
              # GM conjectures
            max_round_duration: @default_max_round_duration,
              # the maximum duration of a round for the GM
            conjectures: [],
              # sets of mutually-exclusive conjectures (by name) - hyper-prior
            contradictions: [],
              # conjecture_name => %{} parameter values of initially believed conjectures
            priors: %{},
              # Candidate actions that, when executed individually or in sequences, could validate a conjecture.
              # Actions are taken either to achieve a goal (to believe in a goal conjecture)
              # or to reinforce belief in an active conjecture (active = conjecture not silenced by a mutually exclusive, more believable one)
            actions: []

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
        [
          %Belief{
            level: 1,
            source: {:gm, gm_def.name},
            about: conjecture_name,
            parameter_values: parameter_values
          } | acc
        ]
      end
    )
  end

  def conjecture(%GenerativeModelDef{conjectures: conjectures}, name) do
    Enum.find(conjectures, &(&1.name == name))
  end
end