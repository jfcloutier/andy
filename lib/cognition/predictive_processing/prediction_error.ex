defmodule Andy.PredictionError do

  @moduledoc "A prediction error reported by a predictor possibly attempting a fulfimmnet option"

  alias __MODULE__

  defstruct predictor_name: nil,
            model_name: nil,
            prediction_name: nil,
            fulfillment_index: nil,
            fulfillment_count: 0

  def new(
        predictor_name: predictor_name,
        model_name: model_name,
        prediction_name: prediction_name,
        fulfillment_index: fulfillment_index,
        fulfillment_count: fulfillment_count
      ) do
    %PredictionError{
      predictor_name: predictor_name,
      model_name: model_name,
      prediction_name: prediction_name,
      fulfillment_index: fulfillment_index,
      fulfillment_count: fulfillment_count
    }
  end

end