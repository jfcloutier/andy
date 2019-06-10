defmodule Andy.Prediction do

  @moduledoc "A prediction that sets belief in a conjecture"

  alias Andy.{ Fulfillment, Prediction }
  import Andy.Utils, only: [as_percept_about: 1]

  @type t :: %__MODULE__{
               name: :atom,
               perceived: [{ tuple(), any, any }],
               precision: atom,
               actuated: [{ atom, any, any }],
               believed: { :not | :is, atom } | nil,
               fulfill_when: [atom],
               fulfill_by: Fulfillment.t | nil,
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
    :fulfill_by,
    :when_fulfilled,
    :true_by_default?,
    :time_sensitive?
  ]

  # prediction name is unique within a conjecture
  defstruct name: nil,
              # e.g. [{ { :sensor, :any, :color, :ambient }, { :gt, 50 }, { :past_secs, 2 } }]
            perceived: [],
              # { :eating, :any, { :past_secs, 5 } }
            actuated: [],
              # {:is | :not, conjecture_name} or nil
            believed: nil,
              # One of :high, :medium, :low
            precision: nil,
              # list of sibling predictions that must already be fulfilled for this one to attempt fulfillment
            fulfill_when: [],
              # prediction fulfillment
            fulfill_by: nil,
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
        if key not in @keys, do: raise "Invalid prediction property #{key}"
        value = Keyword.get(keywords, key)
        case key do
          :perceived ->
            Map.put(acc, :perceived, format_perceived(value))
          :fulfill_by ->
            Map.put(acc, :fulfill_by, format_fulfill_by(value))
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

  def count_fulfillment_options(prediction) do
    case prediction.fulfill_by do
      nil ->
        0
      fulfillment ->
        Fulfillment.count_options(fulfillment)
    end
  end

  def get_actions_at(prediction, fulfillment_index) do
    case prediction.fulfill_by do
      nil ->
        []
      fulfillment ->
        Fulfillment.get_actions_at(fulfillment, fulfillment_index)
    end

  end

  def believing?(%Prediction{ believed: believed }) do
    believed != nil
  end

  def conjecture_name(%Prediction{ believed: {_, conjecture_name} }) do
    conjecture_name
  end

  def fulfillment_conjecture_name(%Prediction{ fulfill_by: fulfillment }) do
    fulfillment.conjecture_name
  end

  def fulfilled_by_believing?(%Prediction{ fulfill_by: fulfillment }) do
    fulfillment != nil and Fulfillment.by_believing?(fulfillment)
  end

  def fulfilled_by_doing?(%Prediction{ fulfill_by: fulfillment }) do
    fulfillment != nil and Fulfillment.by_doing?(fulfillment)
  end

  def fulfillment_summary_at(%Prediction{ fulfill_by: fulfillment }, fulfillment_index) do
    Fulfillment.summary_at(fulfillment, fulfillment_index)
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

  defp format_fulfill_by({ :doing, actions_spec }) do
    Fulfillment.from_doing(actions_spec)
  end

  defp format_fulfill_by({ :believing_in, conjecture_name }) do
    Fulfillment.from_believing(conjecture_name)
  end

end