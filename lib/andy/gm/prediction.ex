defmodule Andy.GM.Prediction do
  @moduledoc """
  A prediction about a belief expected from some sub-believer in a round, should the owning conjecture be valid.
  Predictions, when compared to actual beliefs, can raise prediction errors if the beliefs contradict the predictions
  and do it strongly enough (gain is high enough on the sub-believer sources and the differences between prediction
  and contrarian belief are significant.)
  Prediction errors can cause changes in the next round as to
  which conjectures are valid and which act as goals, as well as shifts in assigned precision weight (adjusting the gain).
  Predictions "flow" to sub-GMs and detectors.
  """

  alias __MODULE__
  require Logger

  @behaviour Andy.GM.Perception

  # The name of the GM which made the prediction;
  defstruct source: nil,
            #  the name of a conjecture of a sub-GM, or a detector name (a detector implies a conjecture)
            conjecture_name: nil,
            # number of times it was carried over from a previous round
            carry_overs: 0,
            # what the predicted belief is about, e.g. "robot1"
            about: nil,
            # The goal, if any, that would be achieved if the prediction comes true in a certain way
            goal: nil,
            # belief value name => predicted value distribution - the expected values for the predicted belief
            # Predictions about a detector => %{detected: value_distribution}
            # Either a single value, a range representing a normal distribution
            # or a list of lists of values, where the first list represent the most expected values
            # and the tail of the list represent the least expected values
            expectations: %{}

  # Perception behaviour

  def source(%Prediction{source: source}), do: source
  def conjecture_name(%Prediction{conjecture_name: conjecture_name}), do: conjecture_name
  def about(%Prediction{about: about}), do: about
  def carry_overs(%Prediction{carry_overs: carry_overs}), do: carry_overs

  def prediction_conjecture_name(prediction) do
    conjecture_name(prediction)
  end

  def values(%Prediction{expectations: nil} = prediction) do
    Logger.warn("nil expectations for #{inspect(prediction)}")
    %{}
  end

  def values(%Prediction{expectations: expectations}) do
    for {key, expectation} <- expectations, into: %{} do
      {key, expected_value(expectation)}
    end
  end

  def prediction_error_size(
        %Prediction{expectations: expectations},
        values
      ) do
    compute_prediction_error_size(values, expectations)
  end

  ### PRIVATE

  # A "complete disbelief" has nil as parameter values
  defp compute_prediction_error_size(nil, _expectations) do
    1.0
  end

  defp compute_prediction_error_size(values, expectations) do
    value_errors =
      Enum.reduce(
        values,
        [],
        fn {param_name, param_value}, acc ->
          expectation = Map.get(expectations, param_name)
          value_error = compute_value_error(param_value, expectation)
          [value_error | acc]
        end
      )

    # Retain the maximum value error
    Enum.reduce(value_errors, 0, &max(&1, &2))
  end

  # Any value is fine
  defp compute_value_error(_value, expectation) when expectation in [nil, []] do
    0
  end

  # How well the believed numerical value fits with the predicted value
  # when the value prediction is a normal distribution defined by a range
  defp compute_value_error(value, low..high = _expectation) when is_number(value) do
    mean = (low + high) / 2
    standard_deviation = (high - low) / 4
    delta = abs(mean - value)

    cond do
      delta <= standard_deviation ->
        0

      delta <= standard_deviation * 1.5 ->
        0.25

      delta <= standard_deviation * 2 ->
        0.5

      delta <= standard_deviation * 3 ->
        0.75

      true ->
        1.0
    end
  end

  # Most expected values at head of the list, least expected value at tail
  defp compute_value_error(value, list = _expectation) when is_list(list) do
    index = Enum.find_index(list, &(value in &1))

    cond do
      index == 0 ->
        0

      index == 1 ->
        0.25

      index == 2 ->
        0.5

      index == 3 ->
        0.75

      true ->
        1.0
    end
  end

  defp compute_value_error(value, single_value = _expectation) do
    if value == single_value do
      0
    else
      1.0
    end
  end

  defp expected_value(low..high) do
    (high - low) / 2
  end

  defp expected_value([firsts | _]) do
    Enum.random(firsts)
  end

  defp expected_value(value) do
    value
  end
end

defimpl Inspect, for: Andy.GM.Prediction do
  def inspect(prediction, _opts) do
    "<#{if prediction.goal == nil, do: "Opinion", else: "Goal"} #{
      inspect(prediction.conjecture_name)
    } of #{inspect(prediction.about)} will be #{inspect(prediction.expectations)}>"
  end
end
