defmodule ConjectureActivation do
  @moduledoc """
  A conjecture about something, instantiated with expected values
  (as sub-domains of the conjecture's param domains), and possibly considered a goal"
  """
  defstruct conjecture_name: nil,
              # e.g. "robot1" vs "robot2"; two conjecture activations can be the same kind of conjecture
              # but about two different subjects
            about: nil,
              # the values the conjecture's parameters are expected to have given what a GM knows
            param_domains: %{},
              # whether the conjecture activation is a goal to be achieved
            goal?: false
end
