defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model's definition"

  # half a second
  @default_max_round_duration 3_000
  @default_max_execution_duration 3_000

  alias __MODULE__
  alias Andy.GM.{Belief, Intention}
  require Logger

  defstruct name: nil,
              # the maximum duration of a round for the GM
            max_round_duration: @default_max_round_duration,
              # the maximum duration of intent execution for the GM
            max_execution_duration: @default_max_execution_duration,
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

    Logger.info("#{gm_def.name}(0): Initial beliefs are #{inspect(initial_beliefs)}")
    initial_beliefs
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

  def contradicts?(gm_def, {conjecture_name, about}, {other_conjecture_name, about}) do
    mutually_exclusive?(gm_def, conjecture_name, other_conjecture_name)
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
    intentions(gm_def, intention_name) |> Enum.all?(&Intention.not_repeatable?(&1))
  end
end
