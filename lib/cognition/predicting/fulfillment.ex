defmodule Andy.Fulfillment do

  @moduledoc "One possible way of fulfilling a prediction"

  # Fulfillment name is unique within a prediction
  defstruct name: nil,
            # generative model to try believing in
            generative_model_name: nil,
            # intents to actualize
            intents: [],
            # how much the precision of lower priority predictions are reduced
            focus: :none # one of :none, :some, :lots, :total

end