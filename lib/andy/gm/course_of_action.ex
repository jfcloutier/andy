defmodule Andy.GM.CourseOfAction do
  @moduledoc "A course of action is a sequence of named Intentions meant to be realized as Intents in an attempt
    to validate some activation of a conjecture"

  require Logger

  alias Andy.GM.{
    GenerativeModelDef,
    CourseOfAction,
    Conjecture,
    ConjectureActivation,
    Efficacy,
    Round,
    Belief,
    Intention,
    PubSub,
    State
  }

  alias Andy.Intent
  import Andy.GM.Utils, only: [info: 1]
  alias __MODULE__

  @max_coa_index 4

  defstruct conjecture_activation: nil,
            intention_names: []

  def of_type?(
        %CourseOfAction{
          conjecture_activation: %ConjectureActivation{
            conjecture: %Conjecture{name: coa_conjecture_name}
          },
          intention_names: coa_intention_names
        },
        {conjecture_name, _},
        intention_names
      ) do
    coa_conjecture_name == conjecture_name and coa_intention_names == intention_names
  end

  def empty?(%CourseOfAction{
        intention_names: coa_intention_names
      }) do
    Enum.count(coa_intention_names) == 0
  end

  def execute_intentions(intentions, belief_values, [round | _previous_rounds] = rounds, state) do
    Logger.info(
      "#{info(state)}: Executing intentions #{inspect(intentions)} given belief values #{
        inspect(belief_values)
      }"
    )

    Enum.reduce(
      intentions,
      round,
      fn intention, %Round{intents: intents} = acc ->
        intent_valuation = intention.valuator.(belief_values)

        if intent_valuation == nil do
          # a nil-valued intent is a noop intent,
          Logger.info(
            "#{info(state)}: Noop intention #{inspect(intention)}. Null intent valuation."
          )

          acc
        else
          # execute valued intent
          %{value: intent_value, duration: duration} = intent_valuation

          intent =
            Intent.new(
              about: intention.intent_name,
              value: intent_value,
              duration: duration
            )

          if not (Intention.not_repeatable?(intention) and
                    would_be_repeated?(intent, rounds)) do
            PubSub.notify_intended(intent)
            %Round{acc | intents: [intent | intents]}
          else
            acc
          end
        end
      end
    )
  end

  # Would an intent be repeated (does the latest remembered intent about the same thing, executed in
  # this or prior rounds, have the same value)?
  defp would_be_repeated?(%Intent{about: about, value: value}, rounds) do
    Enum.reduce_while(
      rounds,
      false,
      fn %Round{intents: intents}, _ ->
        case Enum.find(intents, &(&1.about == about)) do
          nil ->
            {:cont, false}

          %Intent{value: intent_value} ->
            {:halt, intent_value == value}
        end
      end
    )
  end

  # Select a course of action for a conjecture
  # Returns {selected_course_of_action, updated_coa_index, new_coa?} or nil if no CoA
  def possible_courses_of_actions(conjecture_activations, state) do
    Enum.reduce(
      conjecture_activations,
      [],
      fn conjecture_activation, acc ->
        if ConjectureActivation.intention_domain_empty?(conjecture_activation) do
          acc
        else
          if ConjectureActivation.goal?(conjecture_activation) do
            if ConjectureActivation.achieved_now?(conjecture_activation, state) do
              Logger.info(
                "#{info(state)}: Goal achieved for #{inspect(conjecture_activation)}. Nothing to do."
              )

              acc
            else
              # keep trying to achieve the goal
              case select_course_of_action(conjecture_activation, state) do
                nil ->
                  acc

                coa ->
                  [coa | acc]
              end
            end

            # opinion
          else
            if ConjectureActivation.believed_now?(conjecture_activation, state) do
              # keep trying to confirm the opinion
              case select_course_of_action(conjecture_activation, state) do
                nil ->
                  acc

                coa ->
                  [coa | acc]
              end
            else
              acc
            end
          end
        end
      end
    )
  end

  # Select a course of action for a conjecture
  # Returns {selected_course_of_action, updated_coa_index, new_coa?} or nil if no CoA
  defp select_course_of_action(
         %ConjectureActivation{} = conjecture_activation,
         %State{
           efficacies: efficacies,
           courses_of_action_indices: courses_of_action_indices
         } = state
       ) do
    Logger.info(
      "#{info(state)}: Selecting a course of action for conjecture activation #{
        inspect(conjecture_activation)
      }"
    )

    conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

    # Create an untried CoA (shortest possible), give it a hypothetical efficacy (= average efficacy) and add it to the candidates
    coa_index = Map.get(courses_of_action_indices, conjecture_activation_subject, 0)

    # Can be nil if the coa_index duplicates a COA at an earlier index because of non-repeatable intentions
    maybe_untried_coa =
      new_course_of_action(
        conjecture_activation,
        coa_index,
        state
      )

    # Collect as candidates all tried CoAs for similar conjecture activations (same subject)
    # when satisfaction of the conjecture was the same as now (goal achieved/opinion believed vs not)
    # => [{CoA, degree_of_efficacy}, ...]
    satisfied? = ConjectureActivation.satisfied_now?(conjecture_activation, state)

    tried =
      Map.get(efficacies, conjecture_activation_subject, [])
      |> Enum.filter(fn %Efficacy{when_already_satisfied?: when_already_satisfied?} ->
        when_already_satisfied? == satisfied?
      end)
      |> Enum.map(
        &{%CourseOfAction{
           conjecture_activation: conjecture_activation,
           intention_names: &1.intention_names
         }, &1.degree}
      )

    average_efficacy = Efficacy.average_efficacy(tried)

    # Candidates CoA are the previously tried CoAs plus a new one given the average efficacy of the other candidates.
    candidates =
      if maybe_untried_coa == nil or CourseOfAction.empty?(maybe_untried_coa) or
           course_of_action_already_tried?(maybe_untried_coa, tried) do
        if tried == [],
          do: Logger.info("#{info(state)}: Empty tried CoAs and no new untried CoA!")

        tried
      else
        [{maybe_untried_coa, average_efficacy} | tried]
      end
      # Normalize efficacies (sum = 1.0)
      |> Efficacy.normalize_efficacies()

    # Pick a CoA randomly, favoring higher efficacy
    case pick_course_of_action(candidates, state) do
      nil ->
        Logger.info("#{info(state)}: No CoA was picked")
        nil

      course_of_action ->
        # Move the CoA index if we picked an untried CoA
        new_coa? = course_of_action == maybe_untried_coa

        # Are all intentions in the domain of the activated conjecture non-repeatable?
        all_non_repeatable? = all_non_repeatable_intentions?(conjecture_activation, state)

        updated_coa_index =
          if (maybe_untried_coa == nil and not all_non_repeatable?) or new_coa? do
            min(coa_index + 1, @max_coa_index)
          else
            coa_index
          end

        {course_of_action, updated_coa_index, new_coa?}
    end
  end

  defp course_of_action_already_tried?(maybe_untried_coa, tried) do
    tried_coas = Enum.map(tried, fn {coa, _efficacy} -> coa end)
    maybe_untried_coa in tried_coas
  end

  defp new_course_of_action(
         conjecture_activation,
         courses_of_action_index,
         state
       )
       when courses_of_action_index >= @max_coa_index do
    Logger.info("#{info(state)}: Max COA index reached for #{inspect(conjecture_activation)}")
    nil
  end

  defp new_course_of_action(
         %ConjectureActivation{conjecture: %Conjecture{intention_domain: intention_domain}} =
           conjecture_activation,
         courses_of_action_index,
         %State{gm_def: gm_def} = state
       ) do
    Logger.info(
      "#{info(state)}: Creating a candidate new COA for #{inspect(conjecture_activation)}"
    )

    # Convert the index into a list of indices e.g. 5 -> [1,1] , 5th CoA (0-based index) in an intention domain of 3 actions
    index_list = index_list(courses_of_action_index, intention_domain)

    Logger.info(
      "#{info(state)}: index_list = #{inspect(index_list)}, intention_domain = #{
        inspect(intention_domain)
      }"
    )

    intention_names =
      Enum.reduce(
        index_list,
        [],
        fn i, acc ->
          [Enum.at(intention_domain, i) | acc]
        end
      )

    unduplicated_intention_names =
      GenerativeModelDef.unduplicate_intentions(gm_def, intention_names)

    # Note: intention_names are reversed, unduplicated_intention_names are un-reversed

    # Should never happen
    if Enum.count(unduplicated_intention_names) == 0,
      do: Logger.warn("#{info(state)}: Empty intention names for new CoA")

    index_of_coa = index_of_coa(unduplicated_intention_names, intention_domain)

    if(index_of_coa < courses_of_action_index) do
      Logger.info(
        "#{info(state)}: Already tried #{inspect(unduplicated_intention_names)} (#{index_of_coa} < #{
          courses_of_action_index
        })"
      )

      nil
    else
      if all_noops?(unduplicated_intention_names, conjecture_activation, state) do
        Logger.info("#{info(state)}: Noop #{inspect(unduplicated_intention_names)}. No new CoA.")
        nil
      else
        new_coa = %CourseOfAction{
          conjecture_activation: conjecture_activation,
          intention_names: unduplicated_intention_names
        }

        Logger.info("#{info(state)}: Candidate new COA #{inspect(new_coa)}")
        new_coa
      end
    end
  end

  defp all_noops?(intention_names, conjecture_activation, state) when is_list(intention_names) do
    %Round{beliefs: beliefs} = Round.current_round(state)

    case Enum.find(
           beliefs,
           &(Belief.subject(&1) == ConjectureActivation.subject(conjecture_activation))
         ) do
      nil ->
        Logger.warn("#{info(state)}: No belief found for #{inspect(conjecture_activation)}")
        true

      %Belief{} = belief ->
        Enum.all?(intention_names, &noop?(&1, belief, state))
    end
  end

  defp noop?(intention_name, %Belief{values: belief_values}, %State{gm_def: gm_def}) do
    intentions = GenerativeModelDef.intentions(gm_def, intention_name)
    Enum.all?(intentions, &(&1.valuator.(belief_values) == nil))
  end

  defp index_list(courses_of_action_index, [_intention_name]) do
    for _n <- 0..courses_of_action_index, do: 0
  end

  defp index_list(courses_of_action_index, intention_domain) do
    Integer.to_string(courses_of_action_index, Enum.count(intention_domain))
    |> String.to_charlist()
    |> Enum.map(&List.to_string([&1]))
    |> Enum.map(&String.to_integer(&1))
  end

  defp index_of_coa(names, [_name]) do
    Enum.count(names) - 1
  end

  defp index_of_coa(names, domain) do
    {index, ""} =
      Enum.map(names, &Enum.find_index(domain, fn x -> x == &1 end))
      |> Enum.map(&"#{&1}")
      |> Enum.join("")
      |> Integer.parse(Enum.count(domain))

    index
  end

  # Randomly pick a course of action with a probability proportional to its degree of efficacy

  defp pick_course_of_action([], _state) do
    nil
  end

  defp pick_course_of_action([{coa, _degree}], _state) do
    coa
  end

  defp pick_course_of_action(candidate_courses_of_action, state) do
    Logger.info("#{info(state)}: Picking a COA among #{inspect(candidate_courses_of_action)}")

    {ranges_reversed, _} =
      Enum.reduce(
        candidate_courses_of_action,
        {[], 0},
        fn {_coa, degree}, {ranges_acc, top_acc} ->
          {[top_acc + degree | ranges_acc], top_acc + degree}
        end
      )

    ranges = Enum.reverse(ranges_reversed)

    Logger.info(
      "Ranges = #{inspect(ranges)} for courses of action #{inspect(candidate_courses_of_action)}"
    )

    random = Enum.random(0..999) / 1000
    index = Enum.find(0..(Enum.count(ranges) - 1), &(random < Enum.at(ranges, &1)))
    {coa, _efficacy} = Enum.at(candidate_courses_of_action, index)
    Logger.info("#{info(state)}: Picked COA #{inspect(coa)}")
    coa
  end

  defp all_non_repeatable_intentions?(conjecture_activation, %State{gm_def: gm_def}) do
    intention_names = ConjectureActivation.intention_domain(conjecture_activation)
    Enum.all?(intention_names, &GenerativeModelDef.non_repeatable_intentions?(gm_def, &1))
  end
end

defimpl Inspect, for: Andy.GM.CourseOfAction do
  def inspect(coa, _opts) do
    "<CoA #{inspect(coa.intention_names)} for #{inspect(coa.conjecture_activation)}>"
  end
end
