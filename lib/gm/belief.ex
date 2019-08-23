defmodule Andy.GM.Belief do
  @moduledoc "A belief by a detector or generative model"

  alias __MODULE__

  defstruct id: nil,
            # GM name or detector name
            source: nil,
            # conjecture name if from a GM, else detector name is from a detector
            conjecture_name: nil,
            # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
            # value_name => value, or nil if disbelief
            values: nil

  def new(
        source: source,
        conjecture_name: conjecture_name,
        about: about,
        values: values
      ) do
    %Belief{
      id: UUID.uuid4(),
      source: source,
      conjecture_name: conjecture_name,
      about: about,
      values: values
    }
  end

  def believed?(%Belief{values: values}) do
    values != nil
  end

  def subject(%Belief{conjecture_name: conjecture_name, about: about}) do
    {conjecture_name, about}
  end

  def values_match?(%Belief{values: belief_values}, values) do
    case belief_values do
      values ->
        true

      _ ->
        false
    end
  end

  def has_value?(%Belief{values: belief_values}, value_name, value) do
    case Map.get(belief_values, value_name) do
      value ->
        true

      _ ->
        false
    end
  end


  @doc "Is this belief from a generative model?"
  def from_generative_model?(%Belief{source: source}) do
    source not in [:detector, :prediction]
  end
end
