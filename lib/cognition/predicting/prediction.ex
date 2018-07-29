defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  # prediction name is unique within a generative model
  defstruct name: nil,
            perceived: nil,
              # {device_class, device_type, sense, value}
              # or generative model name
            believed: nil,
              # One of :high, :medium, :low, :none
            default_precision: nil,
            fulfillments: []
end