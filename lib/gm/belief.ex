defmodule Andy.GM.Belief do
  @moduledoc "A belief from a detector or generative model"

  alias __MODULE__

  defstruct level: 0, # from 0 to 1, how much the GM that receives them as perceptions believes the named conjecture
              # either :prediction if prediction, :detection if detection, or the name of a GM
            source: nil,
              # conjecture name if from a GM, else detector name is from a detector
            name: nil,
                # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            about: nil,
              # conjecture_parameter_name => value
            parameter_values: %{},
              # How far the parameter values stray from predictions by super-GM(s)
            prediction_error: 0 # Is this belief contrary to prediction? 1 if maximally contrarian.

  @doc """
    Whether a belief overrides another: when the subject is the same (name and about)
    and 1- they from the same source or 2- when the other is a prediction (belief "from sub-believer"
    wins over belief "from prediction")
  """
  def overrides?(
        %Belief{source: source} = belief,
        %Belief{source: other_source} = other_belief
      ) when source == other_source or other_source == :prediction do
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
