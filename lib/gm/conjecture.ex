defmodule Andy.GM.Conjecture do
  @moduledoc """
  An assertion supported, or not, by predicted perceptions.
  """

  defstruct name: nil,
              # parameter_name => domain - a domain is an enumerable of values
            parameter_domains: %{},
              # Functions on a GM's state that produces next-round predictions about
              # perceptions (beliefs from sub-believers(s)) given belief in the conjecture.
              # The conjecture is believed to the extent that the predictions are realized
            predictors: [],
              # A function that generates a belief in the conjecture (sets parameter values and validation level) given perceptions vs. predictions
            validator: nil,
              # A function on a GM's rounds that determines whether the conjecture becomes a transient goal in the next round.
              # While a conjecture is a goal, it can not be silenced by a mutually exclusive conjecture, even if not (yet) believed.
            motivator: nil,
              # Names of actions from the GM definition from which courses of action can be composed and executed to realize the conjecture
            action_domain: []

end