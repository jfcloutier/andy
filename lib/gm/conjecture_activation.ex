defmodule ConjectureActivation do
  @moduledoc """
  A conjecture about something, instantiated with expected values
  (as sub-domains of the conjecture's param domains), and possibly considered a goal"
  """

  alias __MODULE__

  defstruct conjecture_name: nil,
              # e.g. "robot1" vs "robot2"; two conjecture activations can be the same kind of conjecture
              # but about two different subjects
            about: nil,
              # the values the conjecture's parameters are expected to have given what a GM knows
            param_domains: %{},
              # whether the conjecture activation is a goal to be achieved
            goal?: false

  @doc
  """
  Two conjecture activations are mutually exclusive if
  they are from the same conjecture and are about the same object,
  or they are about the same object and from mutually exclusive conjectures
  """
  def mutually_exclusive?(
        %ConjectureActivation{conjecture_name: conjecture_name, about: about},
        %ConjectureActivation{conjecture_name: conjecture_name, about: about},
        _contradictions
      ) do
    true
  end

  def mutually_exclusive?(
        %ConjectureActivation{conjecture_name: conjecture_name, about: about},
        %ConjectureActivation{conjecture_name: other_conjecture_name, about: about},
        contradictions
      ) do
    Enum.any?(contradictions, &(conjecture_name in &1 and other_conjecture_name in &1))
  end

  def mutually_exclusive?(
        %ConjectureActivation{},
        %ConjectureActivation{},
        _contradictions
      ) do
    false
  end

end
