defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  alias Andy.Fulfillment

  @type t :: %__MODULE__{
               perceived: { atom, atom, atom, any } | nil,
               believed: {:not | :is, atom},
               fulfillments: [Fulfillment.t]
             }

  # prediction name is unique within a generative model
  defstruct perceived: nil,
              # or generative model name
            believed: nil,
              # One of :high, :medium, :low, :none
            precision: nil,
              # how much the precision of lower priority predictions are reduced
            fulfillments: []

  def new(
        perceived: { device_class, device_type, sense, value } = _perceived,
        # {device_class, device_type, sense, value}
        precision: default_precision,
         fulfillments: fulfillments
      ) do
    %Prediction{
      perceived: perceived,
      precision: precision,
      fulfillments: fulfillments
    }
  end

  def new(
        believed: believed,
        # {device_class, device_type, sense, value}
        # or generative model name
        precision: precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      believed: believed,
      precision: precision,
      fulfillments: fulfillments
    }
  end

end