defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model's definition"

  @default_max_round_duration 2_000
  @default_min_round_duration 100

  alias __MODULE__
  alias Andy.GM.{Belief, Intention}

  defstruct name: nil,
            # the maximum running duration of a round for the GM
            max_round_duration: @default_max_round_duration,
            # the minimum running duration of a round for the GM
            min_round_duration: @default_min_round_duration,
            # GM conjectures
            conjectures: [],
            # sets of mutually-exclusive conjectures (by name)
            contradictions: [],
            # conjecture_name => %{} parameter values of initial conjecture beliefs
            priors: %{},
            # Candidate intentions that, when executed individually or in sequences, could validate a conjecture.
            # Intentions are taken either to achieve a goal (to believe in a goal conjecture)
            # or to reinforce belief in an active conjecture (active = conjecture not silenced by a mutually exclusive, more believable one)
            # name => intention or [intention, ...] # either single intention or a group of combined intentions
            intentions: %{}

  def initial_beliefs(gm_def) do
    initial_beliefs =
      Enum.reduce(
        gm_def.priors,
        [],
        fn {conjecture_name, %{about: about, values: values}}, acc ->
          [
            %Belief{
              source: {:gm, gm_def.name},
              conjecture_name: conjecture_name,
              about: about,
              values: values
            }
            | acc
          ]
        end
      )

    initial_beliefs
  end

  def min_round_duration(%GenerativeModelDef{min_round_duration: min_round_duration}) do
    min_round_duration
  end

  def has_conjecture?(%GenerativeModelDef{} = gm_def, conjecture_name) do
    conjecture(gm_def, conjecture_name) != nil
  end

  def conjecture(%GenerativeModelDef{conjectures: conjectures}, conjecture_name) do
    Enum.find(conjectures, &(&1.name == conjecture_name))
  end

  def contradicts?(
        %GenerativeModelDef{contradictions: contradictions},
        {conjecture_name, about},
        {other_conjecture_name, about}
      ) do
    Enum.any?(
      contradictions,
      &(conjecture_name != other_conjecture_name and conjecture_name in &1 and
          other_conjecture_name in &1)
    )
  end

  def contradicts?(_gm_def, _subject, _other_subject) do
    false
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

  def unduplicate_intentions(gm_def, intention_names) do
    Enum.reduce(
      intention_names,
      [],
      fn intention_name, acc ->
        do_not_duplicate? =
          intentions(gm_def, intention_name)
          |> Enum.all?(&(Intention.not_repeatable?(&1) or Intention.not_duplicable?(&1)))

        if do_not_duplicate? and intention_name in acc, do: acc, else: [intention_name | acc]
      end
    )
  end

  def non_repeatable_intentions?(gm_def, intention_name) do
    intentions(gm_def, intention_name)
    |> Enum.all?(&(Intention.not_repeatable?(&1) or Intention.not_duplicable?(&1)))
  end
end
