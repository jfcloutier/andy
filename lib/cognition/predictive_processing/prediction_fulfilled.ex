defmodule Andy.PredictionFulfilled do
  @moduledoc "Prediction fulfilled event payload"

  alias __MODULE__

  defstruct model_name: nil,
            prediction: nil

  def new(
        model_name: model_name,
        prediction: prediction
      ) do
    %PredictionFulfilled{
      model_name: model_name,
      prediction: prediction
    }
  end

end