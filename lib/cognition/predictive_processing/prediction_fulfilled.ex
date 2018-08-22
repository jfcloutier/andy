defmodule Andy.PredictionFulfilled do
  @moduledoc "Prediction fulfilled event payload"

  alias __MODULE__

  defstruct predictor_name: nil,
            model_name: nil,
            prediction_name: nil,
            # nil if none else >= 0
            fulfillment_index: nil

  def new(
        predictor_name: predictor_name,
        model_name: model_name,
        prediction_name: prediction_name,
        fulfillment_index: fulfillmen_index
      ) do
    %PredictionFulfilled{
      predictor_name: predictor_name,
      model_name: model_name,
      prediction_name: prediction_name,
      fulfillment_index: fulfillmen_index
    }
  end

end