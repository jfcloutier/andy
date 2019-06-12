defmodule Andy.GM.Conjecture do
  @moduledoc "An assertion about reality supported, or not, by predictions"

  defmodule Predictor do
    @moduledoc "A generator of expected beliefs assuming the conjecture is valid"

    defstruct belief_name: nil,
                # the name of a sub_believer's conjecture
              predicting: nil # A function on a gm's state returning parameter sub-domains for the predicted belief
  end

  defmodule Action do
    @moduledoc "An intent generator"

    defstruct actuator_name: nil,
                # e.g. :locomotion
              intent: nil,
                # e.g. :go_forward
              valuator: nil # fn(gm_state) -> intent value
  end

  defstruct name: nil,
              # A unique name in the context of a generative model
            parameter_domains: %{},
              # parameter_name => domain
            predictors: [],
              # functions on a GM's beliefs (current and priors) that
              # 1- produces a next-round beliefs expected from sub-believers(s)
              # 2- that would support belief in the conjecture
              # 3- in terms of specified parameter sub-domains
            motivator: nil,
              # A function on the state of a GM that determines whether the conjecture is a transient goal
            action_domain: [] # candidate actions that, when executed individually or in sequences,
  # should validate the conjecture
end
