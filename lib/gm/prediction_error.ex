defmodule Andy.GM.PredictionError do
  @moduledoc "A deviation from prediction associated to a belief"

  @behaviour Andy.GM.Perception

  alias Andy.GM.{Belief, Prediction}
  alias __MODULE__

  # the prediction in error
  defstruct prediction: nil,
            # the size of the error: 0..1
            size: 0.0,
            # the belief that contradicts a prediction by the predictor
            belief: nil,
            # number of times it was carried over from a previous round
            carry_overs: 0

  # Perception behaviour

  def source(%PredictionError{
        belief: %Belief{
          source: source
        }
      }),
      do: source

  def name(%PredictionError{
        belief: %Belief{
          name: name
        }
      }),
      do: name

  def about(%PredictionError{
        belief: %Belief{
          about: about
        }
      }),
      do: about

  def parameter_values(%PredictionError{
        belief: %Belief{
          parameter_values: parameter_values
        }
      }),
      do: parameter_values

  def carry_overs(%PredictionError{carry_overs: carry_overs}), do: carry_overs

  def prediction_conjecture_name(%PredictionError{prediction: %Prediction{name: name}}) do
    name
  end
end
