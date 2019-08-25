defmodule Andy.GM.Efficacy do
  @moduledoc "The historical efficacy of a type of course of action to validate a conjecture.
    Efficacy is a measure of the correlation between taking a type of course of action and a conjecture
    about some object becoming believed or staying believed.
    Correlation is gauged by the proximity of the CoA's round to a later round where the conjecture is believed.
    Updates in degrees of efficacy are tempered by prior values."

  # degree of efficacy, float from 0 to 1.0
  defstruct degree: 0,
            # the subject of a course of action
            conjecture_activation_subject: nil,
            # the names of the sequence of intentions of a course of action
            intention_names: [],
            # whether efficacy is for when a conjecture activation was satisfied (vs not) at the time of its execution
            # a conjecture is satisfied if it's an achieved goal or a believed opinion
            when_already_satisfied?: false
end
