defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  alias Andy.Fulfillment

  @type t :: %__MODULE__{
               perceived: [{ tuple(), any, any }],
               believed: { :not | :is, atom } | nil,
               fulfillments: [Fulfillment.t]
             }

  # prediction name is unique within a generative model
  defstruct perceived: [],
              # or generative model name
            believed: nil,
              # One of :high, :medium, :low
            precision: nil,
              # how much the precision of lower priority predictions are reduced
            fulfillments: []

  def new(
        # {:is | :not, <model name>}
        believed: believed,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      believed: believed,
      perceived: perceived,
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        believed: believed,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      believed: believed,
      perceived: [],
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      believed: nil,
      perceived: perceived,
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def summary(prediction) do
    "#{prediction.precision} accuracy prediction that"
    <>
    (cond do
       prediction.believed and prediction.perceived ->
         "#{inspect prediction.believed} (believed) and #{inspect prediction.perceived} (perceived)"
       prediction.believed ->
         "#{inspect prediction.believed} (believed)"
       prediction.perceived ->
         "#{inspect prediction.perceived} (perceived)"
     end)
  end

  def detector_specs(prediction) do
    Enum.map(
      prediction.perceived,
      fn ({ detector_spec, _, _ }) -> detector_spec end
    )
    |> Enum.uniq()
  end

end