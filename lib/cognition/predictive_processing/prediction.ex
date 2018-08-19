defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  alias Andy.{ Fulfillment, Prediction }

  @type t :: %__MODULE__{
               name: :atom,
               perceived: [{ tuple(), any, any }],
               actuated: [{ atom, any, any }],
               believed: { :not | :is, atom } | nil,
               fulfillments: [Fulfillment.t]
             }

  # prediction name is unique within a generative model
  defstruct name: nil,
              # e.g. [{ { :sensor, :any, :color, :ambient }, { :gt, 50 }, { :past_secs, 2 } }]
            perceived: [],
              # { :eating, :any, { :past_secs, 5 } }
            actuated: [],
              # {:is | :not, model_name} or nil
            believed: nil,
              # One of :high, :medium, :low
            precision: nil,
              # list of sibling predictions that must already be fulfilled for this one to attempt fulfillment
            fulfill_when: [],
              # how much the precision of lower priority predictions are reduced
            fulfillments: []

  def new(
        name: name,
        # {:is | :not, <model name>}
        believed: believed,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        actuated: actuated,
        precision: default_precision,
        fulfill_when: fulfill_when,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      believed: believed,
      perceived: format_perceived(perceived),
      actuated: actuated,
      precision: default_precision,
      fulfill_when: fulfill_when,
      fulfillments: fulfillments
    }
  end

  def new(
        name: name,
        # {:is | :not, <model name>}
        believed: believed,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        perceived: perceived,
        actuated: actuated,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      believed: believed,
      perceived: format_perceived(perceived),
      actuated: actuated,
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

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
      perceived: format_perceived(perceived),
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        name: name,
        # {:is | :not, <model name>}
        actuated: actuated,
        precision: default_precision,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      actuated: actuated,
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
      perceived: format_perceived(perceived),
      precision: default_precision,
      fulfillments: fulfillments
    }
  end

  def new(
        name: name,
        # list of {{device_class, device_type, sense}, value desc, timeframe}
        precision: default_precision,
        fulfill_when: fulfill_when,
        fulfillments: fulfillments
      ) do
    %Prediction{
      name: name,
      precision: default_precision,
      fulfill_when: fulfill_when,
      fulfillments: fulfillments
    }
  end

  def summary(prediction) do
    "#{prediction.precision} accuracy prediction that "
    <>
    if prediction.believed != nil, do: " #{inspect prediction.believed} (believed),",
                                   else: ""
                                   <>
                                         if prediction.perceived != [],
                                            do: " #{inspect prediction.perceived} (perceived),",
                                            else: ""
                                            <>
                                                  if prediction.actuated != [],
                                                     do: " #{inspect prediction.actuated} (actuated),"
  end

  def detector_specs(prediction) do
    Enum.map(
      prediction.perceived,
      fn ({ detector_spec, _, _ }) -> detector_spec end
    )
    |> Enum.uniq()
  end

  ### PRIVATE

  defp format_perceived(nil) do
    []
  end

  defp format_perceived(perceived) do
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