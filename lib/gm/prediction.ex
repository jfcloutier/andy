defmodule Andy.GM.Prediction do
  @moduledoc """
  A prediction about a belief expected from some sub-believer in a round, should the owning conjecture be valid.
  Predictions, when compared to actual beliefs, can raise prediction errors if the beliefs contradict the predictions
  and do it strongly enough (gain is high enough on the sub-believer sources and the differences between prediction
  and contrarian belief are significant.)
  Prediction errors can cause changes in the next round as to
  which conjectures are valid and which act as goals, as well as shifts in attention (adjusting the gain on sub-believers).
  Predictions "flow" to sub-believers, causing them, potentially, to shift their winning conjectures to ones
  that would generate the predicted beliefs (when there is no clear winner between competing conjectures).
  """

  alias __MODULE__

  @behaviour Andy.GM.Perception

  # The name of the GM which made the prediction;
  defstruct source: nil,
            #  the name of a conjecture of a sub-GM, or a detector name (a detector implies a conjecture)
            conjecture_name: nil,
            # what the predicted belief is about, e.g. "robot1"
            about: nil,
            # number of times it was carried over from a previous round
            carry_overs: 0,
            # belief value name => predicted value distribution - the expected values for the predicted belief
            # Predictions about a detector => %{detected: value_distribution}
            # Either a range representing a normal distribution
            # or a list of lists of values, where the first list represent the most expected values
            # and the tail of the list represent the least expected values
            value_distributions: %{}

  # Perception behaviour

  def source(%Prediction{source: source}), do: source
  def conjecture_name(%Prediction{conjecture_name: conjecture_name}), do: conjecture_name
  def about(%Prediction{about: about}), do: about
  def carry_overs(%Prediction{carry_overs: carry_overs}), do: carry_overs

  def prediction_conjecture_name(prediction) do
    source(prediction)
  end

  def values(%Prediction{value_distributions: value_distributions}) do
    for {key, value_distribution} <- value_distributions, into: %{} do
      {key, expected_value(value_distribution)}
    end
  end

  def prediction_error_size(
        %Prediction{value_distributions: value_distributions},
        values
      ) do
    compute_prediction_error_size(values, value_distributions)
  end

  # A "complete disbelief" has nil as parameter values
  defp compute_prediction_error_size(nil, _value_distributions) do
    1.0
  end

  defp compute_prediction_error_size(values, value_distributions) do
    value_errors =
      Enum.reduce(
        values,
        [],
        fn {param_name, param_value}, acc ->
          value_distribution = Map.get(value_distributions, param_name)
          value_error = compute_value_error(param_value, value_distribution)
          [value_error | acc]
        end
      )

    # Retain the maximum value error
    Enum.reduce(value_errors, 0, &max(&1, &2))
  end

  # Any value is fine
  defp compute_value_error(_value, value_distribution) when value_distribution in [nil, []] do
    0
  end

  # How well the believed numerical value fits with the predicted value
  # when the value prediction is a normal distribution defined by a range
  defp compute_value_error(value, low..high = _range) when is_number(value) do
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
  defp compute_value_error(value, list) when is_list(list) do
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

  defp expected_value(low..high) do
    (high - low) / 2
  end

  defp expected_value([firsts | _]) do
    Enum.random(firsts)
  end
end
