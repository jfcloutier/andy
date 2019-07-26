defmodule Andy.GM.PredictionError do
  @moduledoc "A deviation from prediction associated to a belief"

  # the name of the GM that made the prediction in error
  defstruct predictor: nil,
              # the size of the error: 0..1
            size: 0.0
end