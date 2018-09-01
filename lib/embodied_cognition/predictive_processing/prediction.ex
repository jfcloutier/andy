defmodule Andy.Prediction do

  @moduledoc "A prediction that sets belief in a generative model"

  alias Andy.{ Fulfillment, Prediction }
  import Andy.Utils, only: [as_percept_about: 1]

  @type t :: %__MODULE__{
               name: :atom,
               perceived: [{ tuple(), any, any }],
               precision: atom,
               actuated: [{ atom, any, any }],
               believed: { :not | :is, atom } | nil,
               fulfill_when: [atom],
               fulfillments: [Fulfillment.t],
               when_fulfilled: [any],
               true_by_default?: boolean(),
               time_sensitive?: boolean()
             }

  @keys [
    :name,
    :perceived,
    :precision,
    :actuated,
    :believed,
    :fulfill_when,
    :fulfillments,
    :when_fulfilled,
    :true_by_default?,
    :time_sensitive?
  ]

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
            fulfillments: [],
              # actions to execute when becoming fulfilled
            when_fulfilled: [],
              # whether a prediction is true until proven false
            true_by_default?: true,
              # whether a prediction is to be reviewed when time passes
            time_sensitive?: false

  def new(keywords) do
    Enum.reduce(
      Keyword.keys(keywords),
      %Prediction{ },
      fn (key, acc) ->
        if not key in @keys, do: raise "Invalid prediction property #{key}"
        value = Keyword.get(keywords, key)
        case key do
          :perceived ->
            Map.put(acc, :perceived, format_perceived(value))
          :fulfillments ->
            Map.put(acc, :fulfillments, format_fulfillments(value))
          _other ->
            Map.put(acc, key, value)
        end
      end
    )
  end

  @doc "Produce a string summarizing a prediction"
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
                                                     do: " #{inspect prediction.actuated} (actuated),", else: ""
  end

  @doc "Generate the detector specs implicit in a prediction about perceptions"
  def detector_specs(prediction) do
    Enum.map(
      prediction.perceived,
      fn ({ detector_spec, _, _ }) -> detector_spec end
    )
    |> Enum.uniq()
  end

  def true_by_default?(%Prediction{ true_by_default?: true_by_default? } = _prediction) do
    true_by_default?
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

  defp format_fulfillments(fulfillments) do
    Enum.map(
      fulfillments,
      fn (fulfillment_spec) ->
        case fulfillment_spec do
          { :actions, actions } ->
            Fulfillment.new(actions: actions)
          { :model, model_name } ->
            Fulfillment.new(model_name: model_name)
        end
      end
    )
  end

end