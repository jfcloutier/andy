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
            # conjecture_parameter_name => value
            parameter_values: %{},
            # How far the parameter values stray from predictions by super-GM(s)
            # Is this belief contrary to prediction? 1 if maximally contrarian.
            # TODO - make PredictionError a struct with size and predictor
            prediction_error: nil

  def new(
        type: type,
        source: source,
        name: name,
        about: about,
        parameter_value: parameter_values
      ) do
    %Belief{id: UUID.uuid4()}
  end

  @doc """
    Whether a belief overrides prediction
  """
  def overrides_prediction?(
        %Belief{type: type} = belief,
        %Belief{type: :prediction} = other_belief
      ) when type in [:detection, :assertion] do
      about_same_thing?(belief, other_belief)
  end

  def overrides?(_belief, _other) do
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
