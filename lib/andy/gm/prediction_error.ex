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

  def conjecture_name(%PredictionError{
        belief: %Belief{
          conjecture_name: conjecture_name
        }
      }),
      do: conjecture_name

  def about(%PredictionError{
        belief: %Belief{
          about: about
        }
      }),
      do: about

  def carry_overs(%PredictionError{carry_overs: carry_overs}), do: carry_overs

  # The name of the conjecture that incorrectly predicted the belief
  def prediction_conjecture_name(%PredictionError{
        prediction: %Prediction{conjecture_name: conjecture_name}
      }) do
    conjecture_name
  end

  def values(%PredictionError{belief: %Belief{values: values}}), do: values
end

defimpl Inspect, for: Andy.GM.PredictionError do
  def inspect(prediction_error, _opts) do
    "Error [#{prediction_error.size}] predicting #{inspect(prediction_error.prediction)}. Got #{
      inspect(prediction_error.belief.values)
    }  (#{prediction_error.carry_overs})"
  end
end
