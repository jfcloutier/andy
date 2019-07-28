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
              #  the name of a conjecture of a sub-GM, or a detector name
            name: nil,
              # what the predicted belief is about, e.g. "robot1"
            about: nil,
              # parameter_name => domain - the expected range of values for the predicted belief
            parameter_sub_domains: %{} # TODO - rename value estimates

  # Perception behaviour

  def source(%Prediction{source: source}), do: source
  def name(%Prediction{name: name}), do: name
  def source(%Prediction{about: about}), do: about
  # TODO - get most expected value
  def parameter_values(%Prediction{parameter_sub_domains: parameter_sub_domains}), do: parameter_sub_domains


end
