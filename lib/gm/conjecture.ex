defmodule Andy.GM.Conjecture do
  @moduledoc """
  An assertion believed in, or not, by predicted perceptions.
  """

  defstruct name: nil,
            # A function on a GM's rounds that activates a conjecture for the next round,
            # setting the expected domain value ranges and possibly making it a goal.
            # fn(conjecture, state) => [conjecture_activation] - can be empty
            activator: nil,
            # parameter_name => domain - a domain is an enumerable of all values parameters of conjecture activations could take
            parameter_domains: %{},
            # Functions fn(conjecture_activation, gm_state) :: prediction that produces next-round predictions about
            # perceptions given belief in the (activated) conjecture.
            predictors: [],
            # Function that sets whether and how the GM believes in an activation of this conjecture given
            # the state of the GM (present and past perceptions, courses of action taken)
            # fn(about, param_domains, gm_state) -> param_values (if believed) or nil (if disbelieved)
            validator: nil,
            # Names of intentions from the GM definition from which courses of action can be composed and executed to realize the conjecture
            intention_domain: []
end
