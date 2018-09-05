defmodule Andy.PredictionError do

  @moduledoc "A prediction error reported by a validator possibly attempting a fulfimmnet option"

  alias __MODULE__

  defstruct validator_name: nil,
            conjecture_name: nil,
            prediction_name: nil,
            fulfillment_index: nil,
            fulfillment_count: 0

  def new(
        validator_name: validator_name,
        conjecture_name: conjecture_name,
        prediction_name: prediction_name,
        fulfillment_index: fulfillment_index,
        fulfillment_count: fulfillment_count
      ) do
    %PredictionError{
      validator_name: validator_name,
      conjecture_name: conjecture_name,
      prediction_name: prediction_name,
      fulfillment_index: fulfillment_index,
      fulfillment_count: fulfillment_count
    }
  end

end