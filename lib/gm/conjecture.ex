defmodule Andy.GM.Conjecture do
  @moduledoc "An assertion about reality supported, or not, by predictions"

  defmodule Action do
    @moduledoc "A valued intent generator"

    defstruct name: nil,
                # the name of the action
              actuator_name: nil,
                # e.g. :locomotion
              intent: nil,
                # e.g. :go_forward
              valuator: nil # fn(gm_state) -> intent value
  end

  defstruct name: nil,
              # A name unique across all generative model definitions
            parameter_domains: %{},
              # parameter_name => domain - a domain is an enumerable of values
            predictors: [],
              # Functions on a GM's rounds that produces next-round predictions about
              # next-round beliefs from sub-believers(s) given belief in the conjecture.
              # The conjecture is believed to the extent that the predictions are realized
            validator: nil,
              # A function that generates a belief in the conjecture (sets parameter values and validation level) given perceptions vs. predictions
            motivator: nil,
              # A function on a GM's rounds that determines whether the conjecture becomes a transient goal in the next round.
              # While a conjecture is a goal, it can not be silenced by a mutually exclusive conjecture, even if not (yet) believed.
            action_domain: [
            ] # Candidate actions that, when executed individually or in sequences, could validate the conjecture.
              # Actions are taken either to achieve a goal (to believe in a goal conjecture)
              # or to reinforce belief in an active conjecture (active = conjecture not silenced by a mutually exclusive, more believable one)
end
