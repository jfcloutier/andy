defmodule Andy.GM.Belief do
  @moduledoc "A belief from a detector or generative model"
  defstruct level: 0,
              # from 0 to 1, how much the GM that receives them as perceptions believes the named conjecture
            source: nil,
              # either :prediction if prediction,
              #                  {:gm, gm_name} if prediction error from a sub-believer GM,
              #                  {:detector, %{class: ..., -- e.g. :sensor
              #                                type: ...,  -- e.g. :infrared
              #                                sense: ..., -- e.g. :proximity
              #                                port: ...   -- needed only if otherwise ambiguous
              #                                }
              #                  } if prediction error from a sub-believer detector
            name: nil,
              # conjecture name if from a GM, else detector name is from a detector
            about: nil,
              # what the conjecture is about, e.g. "robot1" or nil if N/A (e.g. detectors)
            parameter_values: %{},
              # conjecture_parameter_name => value
              # How far the parameter values stray from predictions by super-GM(s)
            prediction_error: 0 # Is this belief contrary to prediction? 1 if maximally contrarian.

  @doc "Whether a belief overrides another"
  def overrides?(%Belief{name: name, about: about}, %Belief{name: name, about: about, source: :prediction}) do
    true
  end

  def overrides?(_belief, _other) do
    false
  end

end
