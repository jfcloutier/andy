defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model's definition"

  # half a second
  @default_max_round_duration 500

  alias __MODULE__
  alias Andy.GM.{Belief, Intention}

  defstruct name: nil,
            # GM conjectures
            max_round_duration: @default_max_round_duration,
            # the maximum duration of a round for the GM
            conjectures: [],
            # sets of mutually-exclusive conjectures (by name) - hyper-prior
            contradictions: [],
            # conjecture_name => %{} parameter values of initial conjecture beliefs
            priors: %{},
            # Candidate intentions that, when executed individually or in sequences, could validate a conjecture.
            # Intentions are taken either to achieve a goal (to believe in a goal conjecture)
            # or to reinforce belief in an active conjecture (active = conjecture not silenced by a mutually exclusive, more believable one)
            # name => intention or [intention, ...] # either single intention or a group of combined intentions
            intentions: %{},
            # Whether this GM is always activating conjectures
            hyper_prior: false

  def initial_beliefs(gm_def) do
    Enum.reduce(
      gm_def.priors,
      [],
      fn conjecture_name, acc ->
        case Map.get(gm_def.priors, conjecture_name) do
          nil ->
            acc

          values ->
            [
              %Belief{
                source: {:gm, gm_def.name},
                about: conjecture_name,
                values: values
              }
              | acc
            ]
        end
      end
    )
  end

  def has_conjecture?(%GenerativeModelDef{} = gm_def, conjecture_name) do
    conjecture(gm_def, conjecture_name) != nil
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

  # An intention name may be associated with a group of intentions or a single one.
  # Always return a group
  def intentions(%GenerativeModelDef{intentions: intentions}, intention_name) do
    case Map.get(intentions, intention_name, []) do
      group when is_list(group) ->
        group

      intention ->
        [intention]
    end
  end

  def hyper_prior?(%GenerativeModelDef{hyper_prior: hyper_prior?}) do
    hyper_prior?
  end

  def unduplicate_non_repeatables(gm_def, intention_names) do
    Enum.reduce(
      intention_names,
      [],
      fn intention_name, acc ->
        not_repeatable? = intentions(gm_def, intention_name) |> Enum.all?(&(not &1.repeatable))
        if not_repeatable? and intention_name in acc, do: acc, else: [intention_name | acc]
      end
    )
  end

  def non_repeatable_intentions?(gm_def, intention_name) do
    intentions(gm_def, intention_name) |> Enum.all?(&(Intention.not_repeatable?(&1)))
  end
end
