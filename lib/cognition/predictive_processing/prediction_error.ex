defmodule Andy.PredictionError do

  @moduledoc "A prediction error"

  defstruct generative_model_name: nil,
            prediction_name: nil,
            # actual belief probability or percept value
            actual_value: nil

end