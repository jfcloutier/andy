defmodule Andy.Prediction do

  @moduledoc "A prediction by a generative model"

  alias Andy.{ Fulfillment, Prediction }
  import Andy.Utils, only: [as_percept_about: 1]

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

  def new(keywords) do
    Enum.reduce(
      Keyword.keys(keywords),
      %Prediction{ },
      fn (key, acc) ->
        value = Keyword.get(keywords, key)
        case key do
          :perceived ->
            Map.put(acc, :perceived, format_perceived(value))
          _other ->
            Map.put(acc, key, value)
        end
      end
    )
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

 end