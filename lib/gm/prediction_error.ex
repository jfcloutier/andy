defmodule Andy.GM.PredictionError do
  @moduledoc "A deviation from prediction associated to a belief"

  @behaviour Andy.GM.Perception

  # the name of the GM that made the prediction in error
  defstruct predictor: nil,
              # the size of the error: 0..1
            size: 0.0,
              # the belief that contradicts a prediction by the predictor
            belief: nil

  # Perception behaviour

  def source(
        %PredictionError{
          belief: %Belief{
            source: source
          }
        }
      ), do: source
  def name(
        %PredictionError{
          belief: %Belief{
            name: name
          }
        }
      ), do: name
  def source(
        %PredictionError{
          belief: %Belief{
            about: about
          }
        }
      ), do: about
  def parameter_values(
        %PredictionError{
          belief: %Belief{
            parameter_values: parameter_values
          }
        }
      ), do: parameter_values

end
