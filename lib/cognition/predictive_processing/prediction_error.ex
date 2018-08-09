defmodule Andy.PredictionError do

  @moduledoc "A prediction error"

  alias __MODULE__

  defstruct predictor_name: nil,
            model_name: nil,
            prediction_name: nil

  def new(
        predictor_name: predictor_name,
        model_name: model_name,
        prediction_name: prediction_name
      ) do
    %PredictionError{
      predictor_name: predictor_name,
      model_name: model_name,
      prediction_name: prediction_name
    }
  end

end