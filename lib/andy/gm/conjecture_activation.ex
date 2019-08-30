defmodule Andy.GM.ConjectureActivation do
  @moduledoc """
  A conjecture instantiated about something, and possibly considered a goal"
  """

  alias __MODULE__
  alias Andy.GM.Conjecture

  defstruct conjecture: nil,
            # e.g. "robot1" vs "robot2"; two conjecture activations can be the same kind of conjecture
            # but about two different subjects
            about: nil,
            # nil if the conjecture is an "opinion", else fn(belief_values)::boolean
            # that evaluates if the conjecture-as-goal is achieved
            goal: nil

  @doc "Two conjecture activations are mutually exclusive if they are from the same conjecture
  and are about the same object, or they are about the same object and from mutually
  exclusive conjectures"

  def conjecture_name(%ConjectureActivation{conjecture: %Conjecture{name: name}}) do
    name
  end

  def mutually_exclusive?(
        %ConjectureActivation{conjecture: conjecture, about: about},
        %ConjectureActivation{conjecture: conjecture, about: about},
        _contradictions
      ) do
    true
  end

  def mutually_exclusive?(
        %ConjectureActivation{conjecture: %Conjecture{name: conjecture_name}, about: about},
        %ConjectureActivation{conjecture: %Conjecture{name: other_conjecture_name}, about: about},
        contradictions
      )
      when conjecture_name != other_conjecture_name do
    Enum.any?(contradictions, &(conjecture_name in &1 and other_conjecture_name in &1))
  end

  def mutually_exclusive?(
        %ConjectureActivation{},
        %ConjectureActivation{},
        _contradictions
      ) do
    false
  end

  @doc "The subject of the conjecture activation, namely the name of the conjecture activated
  and the object of the activation (e.g. robot1)"
  def subject(%ConjectureActivation{conjecture: %Conjecture{name: conjecture_name}, about: about}) do
    {conjecture_name, about}
  end

  def goal?(%ConjectureActivation{goal: goal}) do
    goal != nil
  end

  def intention_domain_empty?(%ConjectureActivation{
        conjecture: %Conjecture{intention_domain: intention_domain}
      }) do
    Enum.count(intention_domain) == 0
  end
end
