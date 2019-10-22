defmodule Andy.GM.Efficacy do
  @moduledoc "The historical efficacy of a type of course of action to validate a conjecture.
    Efficacy is a measure of the correlation between taking a type of course of action and a conjecture
    about some object becoming believed or staying believed.
    Correlation is gauged by the proximity of the CoA's round to a later round where the conjecture is believed.
    Updates in degrees of efficacy are tempered by prior values."

  alias Andy.GM.{Belief, Efficacy, CourseOfAction, Round, ConjectureActivation, State}
  import Andy.GM.Utils, only: [info: 1]
  require Logger

  # degree of efficacy, float from 0 to 1.0
  defstruct degree: 0,
            # the subject of a course of action
            conjecture_activation_subject: nil,
            # the names of the sequence of intentions of a course of action
            intention_names: [],
            # whether efficacy is for when a conjecture activation was satisfied (vs not) at the time of its execution
            # a conjecture is satisfied if it's an achieved goal or a believed opinion
            when_already_satisfied?: false

  def update_efficacies_from_belief(
        %Belief{} = belief,
        efficacies,
        state
      ) do
    conjecture_satisfied? = Belief.satisfies_conjecture?(belief)
    subject_of_belief = Belief.subject(belief)

    case Map.get(efficacies, subject_of_belief) do
      nil ->
        efficacies

      conjecture_efficacies ->
        revised =
          revise_conjecture_efficacies(conjecture_efficacies, conjecture_satisfied?, state)

        Logger.info(
          "#{info(state)}: Efficacies for #{inspect(subject_of_belief)} given conjecture satisfied is #{
            conjecture_satisfied?
          } updated to #{inspect(revised)}"
        )

        Map.put(efficacies, subject_of_belief, revised)
    end
  end

  # Return [{coa, efficacy}, ...] such that the sum of all efficacies == 1.0
  def normalize_efficacies(candidate_courses_of_action) do
    non_zeroized =
      Enum.map(
        candidate_courses_of_action,
        fn {cao, degree} ->
          {cao, max(0.1, degree)}
        end
      )

    sum =
      Enum.reduce(
        non_zeroized,
        0,
        fn {_cao, degree}, acc ->
          degree + acc
        end
      )

    if sum == 0 do
      non_zeroized
    else
      Enum.reduce(
        non_zeroized,
        [],
        fn {cao, degree}, acc ->
          [{cao, degree / sum} | acc]
        end
      )
    end
  end

  def update_efficacies_with_new_coa(
        efficacies,
        %CourseOfAction{
          conjecture_activation: conjecture_activation,
          intention_names: intention_names
        } = coa,
        state
      ) do
    Logger.info("#{info(state)}: Updating efficacies with new COA #{inspect(coa)}")
    conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

    new_efficacy = %Efficacy{
      conjecture_activation_subject: ConjectureActivation.subject(conjecture_activation),
      when_already_satisfied?: ConjectureActivation.satisfied_now?(conjecture_activation, state),
      degree: 0,
      intention_names: intention_names
    }

    Logger.info("#{info(state)}: Adding efficacy #{inspect(new_efficacy)}")

    updated_efficacies =
      Map.put(
        efficacies,
        conjecture_activation_subject,
        [new_efficacy | Map.get(efficacies, conjecture_activation_subject, [])]
      )

    updated_efficacies
  end

  def average_efficacy([]) do
    1.0
  end

  def average_efficacy(tried) do
    (Enum.map(tried, &elem(&1, 1))
     |> Enum.sum()) / Enum.count(tried)
  end

  # Revise the efficacies of various CoAs executed in all rounds to validate a conjecture as they correlate
  # to the current belief (or non-belief) in the conjecture.
  defp revise_conjecture_efficacies(
         conjecture_activation_efficacies,
         conjecture_satisfied?,
         state
       ) do
    Logger.info(
      "#{info(state)}: Revising efficacies #{inspect(conjecture_activation_efficacies)} given conjecture satisfied is #{
        conjecture_satisfied?
      }"
    )

    Enum.reduce(
      conjecture_activation_efficacies,
      [],
      fn %Efficacy{} = efficacy, acc ->
        updated_degree = update_efficacy_degree(efficacy, conjecture_satisfied?, state)

        [%Efficacy{efficacy | degree: updated_degree} | acc]
      end
    )
  end

  # Update the degree of efficacy of a type of CoA in achieving belief across all (remembered) rounds
  # where it was executed, given that the belief was already achieved or not at the time of the CoA's execution
  defp update_efficacy_degree(
         %Efficacy{
           conjecture_activation_subject: conjecture_activation_subject,
           intention_names: intention_names,
           when_already_satisfied?: when_already_satisfied?,
           degree: degree
         },
         conjecture_satisfied?,
         %State{
           rounds: rounds
         }
       ) do
    number_of_rounds = Enum.count(rounds)

    # Find the indices of rounds where the type of CoA was executed
    # and where what the conjecture was about (its subject) is already satisfied (or not)
    indices_of_rounds_with_coa =
      Enum.reduce(
        0..(number_of_rounds - 1),
        [],
        fn index, acc ->
          %Round{courses_of_action: courses_of_action} = Enum.at(rounds, index)

          if Enum.any?(
               courses_of_action,
               &(CourseOfAction.of_type?(&1, conjecture_activation_subject, intention_names) and
                 when_already_satisfied? == conjecture_satisfied?)
             ) do
            [index | acc]
          else
            acc
          end
        end
      )
      |> Enum.reverse()

    number_of_rounds_with_coa = Enum.count(indices_of_rounds_with_coa)

    # Estimate how much each CoA execution correlates to believing in the conjecture it was meant to validate
    # The closer the CoA execution is to this round, the greater the correlation
    impact = if conjecture_satisfied?, do: 1.0, else: 0.0

    # The correlation of a CoA in a round to a current belief is the closeness of the round to the current one
    # e.g. [4/4, 2/4, 1/4]
    correlations =
      Enum.reduce(
        indices_of_rounds_with_coa,
        [],
        fn round_index, acc ->
          closeness = (number_of_rounds - round_index) / number_of_rounds_with_coa
          round_correlation = closeness * impact
          [round_correlation | acc]
        end
      )

    # Get the normalized, cumulative correlated impact on belief by a CoA's executions
    # from this round and previous rounds
    # e.g. maximum = sum(4/4, 3/4, 2/4, 1/4)
    maximum = Enum.sum(1..number_of_rounds) / number_of_rounds
    normalized_correlation = Enum.sum(correlations) / maximum

    # Give equal weight to the correlation with the CoA causing this belief and the prior degree of efficacy of the CoA
    # in achieving belief in the same conjecture in all previous rounds.
    (normalized_correlation + degree) / 2.0
  end

end

defimpl Inspect, for: Andy.GM.Efficacy do
  def inspect(efficacy, _opts) do
    "<Efficacy of doing #{inspect(efficacy.intention_names)} is #{efficacy.degree} when #{
      inspect(efficacy.conjecture_activation_subject)
    } is #{if efficacy.when_already_satisfied?, do: "", else: "not"} already satisfied>"
  end
end
