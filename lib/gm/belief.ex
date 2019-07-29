defmodule Andy.GM.Belief do
  @moduledoc "A belief by a detector or generative model"

  alias __MODULE__

  defstruct id: nil,
            # GM name or detector name
            source: nil,
            # conjecture name if from a GM, else detector name is from a detector
            name: nil,
            # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
            # conjecture_parameter_name => value, or nil if disbelief
            parameter_values: nil,
            # TODO remove
            level: nil

  def new(
        source: source,
        name: name,
        about: about,
        parameter_values: parameter_values
      ) do
    %Belief{
      id: UUID.uuid4(),
      source: source,
      name: name,
      about: about,
      parameter_values: parameter_values
    }
  end

  @doc "Is this belief from a generative model?"
  def from_generative_model?(%Belief{source: source}) do
    source not in [:detector, :prediction]
  end
end
