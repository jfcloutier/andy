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

  defp expected_value(low..high) do
    (high - low) / 2
  end

  defp expected_value([firsts | _])  do
    Enum.random(firsts)
  end

end
