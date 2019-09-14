defmodule Andy.GM.Belief do
  @moduledoc "A belief by a detector or generative model"

  alias __MODULE__
  import Andy.Utils, only: [does_match?: 2]

  # GM name or detector name
  defstruct source: nil,
            # conjecture name if from a GM, else detector name is from a detector
            conjecture_name: nil,
            # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
            # the goal, if any, to be achieved
            goal: nil,
            # value_name => value, or nil if disbelief
            values: nil,
            # the number of times the belief was carried over from a previous round
            carry_overs: 0

  def new(
        source: source,
        conjecture_name: conjecture_name,
        about: about,
        goal: goal,
        values: values
      ) do
    %Belief{
      source: source,
      conjecture_name: conjecture_name,
      about: about,
      goal: goal,
      values: values
    }
  end

  def values(%Belief{values: values}) do
    values
  end

  def believed?(%Belief{values: values}) do
    values != nil
  end

  def satisfies_conjecture?(%Belief{values: nil}) do
    false
  end

  def satisfies_conjecture?(%Belief{goal: nil, values: values}) do
    values != nil
  end

  def satisfies_conjecture?(%Belief{goal: goal, values: values}) do
    goal.(values)
  end

  def subject(%Belief{conjecture_name: conjecture_name, about: about}) do
    {conjecture_name, about}
  end

  def values_match?(%Belief{values: values}, match) do
    Enum.all?(match, fn {key, val} -> Map.get(values, key) == val end)
  end

  def has_value?(%Belief{values: belief_values}, value_name, value) do
    does_match?(Map.get(belief_values, value_name), value)
  end

  @doc "Is this belief from a generative model?"
  def from_generative_model?(%Belief{source: source}) do
    source not in [:detector, :prediction]
  end

  def increment_carry_overs(%Belief{carry_overs: carry_overs} = belief) do
    %Belief{belief | carry_overs: carry_overs + 1}
  end
end

defimpl Inspect, for: Andy.GM.Belief do
  def inspect(belief, _opts) do
    "<Belief that #{if belief.goal == nil, do: "opinion", else: "goal"} #{
      inspect(belief.conjecture_name)
    } of #{inspect(belief.about)} is #{inspect(belief.values)} (#{belief.carry_overs})>"
  end
end
