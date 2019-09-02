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
            # fn(conjecture, rounds, about) => [conjecture_activation] - can be empty
            activator: nil,
            # Functions fn(conjecture_activation, rounds) :: prediction || nil.
            # A predictor produces a prediction (or none) about perceptions given the (activated) conjecture.
            # Only the :conjecture_name (of a sub_gm), :about and :expectations of instantiated prediction need be set by predictors
            predictors: [],
            # Function that sets the values of the belief in this activated conjecture given
            # the state of the GM (present and past perceptions, courses of action taken)
            # fn(conjecture_activation, rounds) -> param_values (if believed) or nil (if disbelieved)
            valuator: nil,
            # Names of intentions from the GM definition from which courses of action can be composed and executed to realize the conjecture
            intention_domain: [],
            # Runs activator even if no related prediction received
            self_activated: false

  def activate(%Conjecture{} = conjecture, about: about, goal: goal) do
    %ConjectureActivation{
      conjecture: conjecture,
      about: about,
      goal: goal
    }
  end

  def activate(%Conjecture{} = conjecture, about: about) do
    %ConjectureActivation{
      conjecture: conjecture,
      about: about,
      goal: nil
    }
  end

  def self_activated?(%Conjecture{self_activated: self_activated}) do
    self_activated
  end
end

defimpl Inspect, for: Andy.GM.Conjecture do
  def inspect(conjecture, _opts) do
    "<Conjecture #{inspect(conjecture.name)} with intention domain #{
      inspect(conjecture.intention_domain)
    }#{if conjecture.self_activated, do: " (self-activated)", else: ""}>"
  end
end
