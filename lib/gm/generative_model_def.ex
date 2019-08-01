defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model's definition"

  # half a second
  @default_max_round_duration 500

  alias __MODULE__
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
            # Candidate intentions that, when executed individually or in sequences, could validate a conjecture.
            # Intentions are taken either to achieve a goal (to believe in a goal conjecture)
            # or to reinforce belief in an active conjecture (active = conjecture not silenced by a mutually exclusive, more believable one)
            # intention_name => intention
            # Should always include a do-nothing intention
            intentions: %{}

  def initial_beliefs(gm_def) do
    Enum.reduce(
      gm_def.priors,
      [],
      fn conjecture_name, acc ->
        values = Map.get(gm_def.priors, conjecture_name)

        [
          %Belief{
            source: {:gm, gm_def.name},
            about: conjecture_name,
            values: values
          }
          | acc
        ]
      end
    )
  end

  def conjecture(%GenerativeModelDef{conjectures: conjectures}, conjecture_name) do
    Enum.find(conjectures, &(&1.name == conjecture_name))
  end

  def mutually_exclusive?(
        %GenerativeModelDef{contradictions: contradictions},
        conjecture_name,
        other
      ) do
    Enum.any?(contradictions, &(conjecture_name in &1 and other in &1))
  end

  def intention(%GenerativeModelDef{intentions: intentions}, intention_name) do
    Map.get(intentions, intention_name)
  end
end
