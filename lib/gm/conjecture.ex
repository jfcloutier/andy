defmodule Andy.GM.Conjecture do
  @moduledoc """
  An assertion believed in, or not, by predicted perceptions.
  """

  alias Andy.GM.ConjectureActivation
  alias __MODULE__

  defstruct name: nil,
            # A function on a GM's rounds that activates a conjecture for the next round,
            # typically based on the history of prior beliefs,
            # setting the expected domain value ranges and possibly making it a goal.
            # fn(conjecture, rounds) => [conjecture_activation] - can be empty
            activator: nil,
            # value_name => domain - a domain is an enumerable of all values parameters of conjecture activations could take
            value_domains: %{},
            # Functions fn(conjecture_activation, rounds) :: prediction that produces next-round predictions about
            # perceptions given the (activated) conjecture.
            predictors: [],
            # Function that sets the values of the belief in this activated conjecture given
            # the state of the GM (present and past perceptions, courses of action taken)
            # fn(conjecture_activation,rounds) -> param_values (if believed) or nil (if disbelieved)
            valuator: nil,
            # Names of intentions from the GM definition from which courses of action can be composed and executed to realize the conjecture
            intention_domain: []

  def activate(%Conjecture{} = conjecture, about: about, goal?: goal?) do
    %ConjectureActivation{
      conjecture: conjecture,
      about: about,
      goal?: goal?
    }
  end
end
