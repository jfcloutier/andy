defmodule Andy.GM.Belief do
  @moduledoc "A belief from a detector or generative model"

  alias __MODULE__

  defstruct id: nil,
              # either :prediction, :detection or :assertion
            type: nil,
              # GM name or detector name
            source: nil,
              # conjecture name if from a GM, else detector name is from a detector
            name: nil,
              # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
              # conjecture_parameter_name => value, or nil if disbelief
            parameter_values: nil,
              # If the belief is from a prediction error, its size
            prediction_error_size: 0

  def new(
        type: type,
        source: source,
        name: name,
        about: about,
        parameter_values: parameter_values
      ) do
    %Belief{
      id: UUID.uuid4(),
      type: type,
      source: source,
      name: name,
      about: about,
      parameter_values: parameter_values
    }
  end

  def prediction_error_replaces_prediction?(_belief, _other) do
    false
  end

  def about_same_thing?(
        %Belief{name: name, about: about},
        %Belief{name: name, about: about}
      ) do
    true
  end

  def about_same_thing?(
        _belief,
        _other_belief
      ) do
    false
  end

  @doc "Is this belief from a generative model?"
  def from_generative_model?(%Belief{source: source}) do
    source not in [:detector, :prediction]
  end
end
