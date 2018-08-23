defmodule Andy.PredictionFulfilled do
  @moduledoc "Prediction fulfilled event payload"

  alias __MODULE__

  defstruct predictor_name: nil,
            model_name: nil,
            prediction_name: nil,
            # nil if none else >= 0
            fulfillment_index: nil,
            fulfillment_count: 0

  def new(
        predictor_name: predictor_name,
        model_name: model_name,
        prediction_name: prediction_name,
        fulfillment_index: fulfillment_index,
        fulfillment_count: fulfillment_count
      ) do
    %PredictionFulfilled{
      predictor_name: predictor_name,
      model_name: model_name,
      prediction_name: prediction_name,
      fulfillment_index: fulfillment_index,
      fulfillment_count: fulfillment_count
    }
  end

end