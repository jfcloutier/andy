defmodule Andy.PredictionError do

  @moduledoc "A prediction error"

  alias __MODULE__

  defstruct model_name: nil,
            prediction_name: nil

  def new(
        model_name: model_name,
        prediction_name: prediction_name
      ) do
    %PredictionError{
      model_name: model_name,
      prediction_name: prediction_name
    }
  end

end