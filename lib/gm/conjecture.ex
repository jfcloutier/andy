defmodule Andy.GM.Conjecture do
  @moduledoc "An assertion about reality supported, or not, by predictions"

  defmodule Action do
    @moduledoc "An intent generator"

    defstruct name: nil,
                # the name of the action
              actuator_name: nil,
                # e.g. :locomotion
              intent: nil,
                # e.g. :go_forward
              valuator: nil # fn(gm_state) -> intent value
  end

  defstruct name: nil,
              # A unique name
            parameter_domains: %{},
              # parameter_name => domain - a domain is an enumerable of values
            predictors: [],
              # functions on a GM's rounds (a GM's memory) that
              # 1- produces next-round predictions about next-round beliefs from sub-believers(s) given belief in the conjecture
            motivator: nil,
              # A function on a GM's rounds that determines whether the conjecture becomes a transient goal in the next round
            action_domain: [
            ] # candidate actions that, when executed individually or in sequences, could validate the conjecture, whether it's a goal or not
end
