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

  defstruct belief_name: nil,
              # the name of a sub_believer's belief (same as name of the validated conjecture)
            parameter_sub_domains: %{
            } # parameter_name => domain - the expected range of values for the predicted belief
end

