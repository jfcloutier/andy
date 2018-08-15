defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  alias Andy.{ Fulfillment, Prediction }

  @type t :: %__MODULE__{
               name: :atom,
               perceived: [{ tuple(), any, any }],
               believed: { :not | :is, atom } | nil,
               fulfillments: [Fulfillment.t]
             }

  # prediction name is unique within a generative model
  defstruct name: nil,
            perceived: [],
              # or generative model name
            believed: nil,
              # One of :high, :medium, :low
            precision: nil,
              # how much the precision of lower priority predictions are reduced
            fulfillments: []

  def new(
        name: name,
        # {:is | :not, <model name>}
        believed: believed,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      believed: believed,
      perceived: process_perceived(perceived),
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        name: name,
        believed: believed,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      believed: believed,
      perceived: [],
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        name: name,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      believed: nil,
      perceived: process_perceived(perceived),
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

  ### PRIVATE

  defp process_perceived(nil) do
    []
  end

  defp process_perceived(perceived) do
    Enum.map(
      perceived,
      fn ({ percept_specs, predicate, timing }) ->
        { as_percept_about(percept_specs), predicate, timing }
      end
    )
  end

  defp as_percept_about(percept_specs) do
    if is_map(percept_specs) do
      percept_specs
    else
      { class, port, type, sense } = percept_specs
      %{
        class: class,
        port: port,
        type: type,
        sense: sense
      }
    end
  end

end