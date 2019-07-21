defmodule Andy.GM.Conjecture do
  @moduledoc """
  An assertion believed in, or not, by predicted perceptions.
  """

  defstruct name: nil,
              # A function on a GM's rounds that activates a conjecture for the next round,
              # setting the expected domain value ranges and possibly making it a goal.
              # fn(conjecture, state) => [conjecture_activation]
            activator: nil,
              # parameter_name => domain - a domain is an enumerable of all values parameters of conjecture activations could take
            parameter_domains: %{},
              # Functions on a GM's state that produces next-round predictions about
              # perceptions (beliefs from sub-believers(s)) given belief in the (activated) conjecture.
            predictors: [],
              # Names of intentions from the GM definition from which courses of action can be composed and executed to realize the conjecture
            intention_domain: []

end