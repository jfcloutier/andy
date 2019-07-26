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

  # The name of the GM which is the source of the prediction;
  defstruct source: nil,
              #  a conjecture or detector name
            name: nil,
              # what the predicted belief is about, e.g. "robot1"
            about: nil,
              # {name, about} of a belief
            parameter_sub_domains: %{}

  # parameter_name => domain - the expected range of values for the predicted belief
end
