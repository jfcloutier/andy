defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  # Round start:
  #           - Start timer on round timeout
  #           - Copy over all the perceptions from the previous round that have not already been copied too often
  #             (a GM's perceptions are prediction errors from sub-GMs and detectors,
  #             and predictions made by the GM that are not contradicted by prediction errors)
  #           - Copy over all the received predictions from the previous round that have not already been copied
  #             too often
  #           - Carry over beliefs from the previous round (they will all be replaced upon completing this round
  #             by new beliefs)
  #           - Activate conjectures (as goals or not, avoiding mutual exclusions) given current and previous beliefs
  #           - Remove prior perceptions that are attributable to conjectures that are mutually exclusive of this
  #             round's conjecture activations
  #           - Make predictions about perceptions in this round from the conjecture activations, given carried-over
  #             beliefs and perceptions. Add them to perceptions, replacing obsoleted perceptions.
  #           - Report these predictions
  #               - Sub-GMs accumulate them as received predictions (may lead to them producing prediction errors)
  #               - Any detector that could directly verify a prediction is triggered
  #           - If there is no conjecture activation for this round, remove the carried-over beliefs
  #           - and complete the round right away
  #
  # During round (until complete):
  #           - Receive inactive round and completed round notifications from sub-GMs; mark them as reported-in
  #             (i.e. they made their contributions to this round)
  #                 - Check if the round ready for completion (all considered sub-GMs reported in - with precision weight > 0).
  #                 - If so complete it.
  #           - Receive predictions from super-GMs and replace overridden received predictions
  #             (overridden if the have the same subject - conjecture name and object it is about -
  #             and are from the same GM)
  #           - Receive prediction errors from sub-GMs and detectors as perceptions and replace overridden perceptions
  #             (a prediction error overrides the prediction it corrects)
  #
  # Round completion (no conjecture was activated, or all sub-GMs have reported in, or the round has timed out waiting):
  #           - Update precision weighing of sub-GMs given prediction errors from competing sources of perceptions
  #               - Reduce precision weight of the competing sub-GMs that deviate more from a given prediction
  #                 (confirmation bias)
  #               - Increase precision weight of the sub-GMs that deviate the least or have no competitor
  #           - When two perceptions are about the same thing, retain only the more trustworthy
  #               - A GM retains one effective perception about something (e.g. can't perceive two distances to a wall)
  #           - Compute the new GM's beliefs for each activated conjecture given GM's present and past rounds,
  #             and determine if they are prediction errors (i.e. beliefs that contradict or are misaligned with
  #             received predictions). The new beliefs replace all beliefs carried over from the previous round.
  #           - Report the prediction errors
  #           - Update course of action efficacies given current belief (i.e. re-evaluate what past courses of action
  #             seem to have worked best to achieve a belief or to maintain it)
  #           - Choose a course of action for each conjecture activation, influenced by historical efficacy, to
  #             hopefully make belief in the activated conjecture true or keep it true in the next round
  #           - Execute the chosen courses of action by reporting valued intents from each one's sequence of intentions
  #           - Mark round completed and report completion
  #           - Drop obsolete rounds (from too distant past)
  #           - Add a new round and start it

  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.Intent

  alias Andy.GM.{
    PubSub,
    GenerativeModelDef,
    Belief,
    Conjecture,
    ConjectureActivation,
    Prediction,
    PredictionError,
    Perception,
    LongTermMemory,
    Intention
  }

  # for how long rounds are remembered (long-term memory)
  @forget_round_after_secs 60
  # How many rounds a perception/received prediction be carried over (short-term memory)
  @max_carry_overs 3

  defmodule State do
    defstruct gm_def: nil,
              # a GenerativeModelDef - static
              # Names of the generative models this GM feeds into according to the GM graph
              super_gm_names: [],
              # Names of the generative models that feed into this GM according to the GM graph
              sub_gm_names: [],
              # Conjecture activations, some of which can be goals. One conjecture can lead to multiple activations,
              # each about a different object
              conjecture_activations: [],
              # latest rounds of activation of the generative model
              rounds: [],
              # precision weights currently given to sub-GMs and detectors => float from 0 to 1 (full weight)
              precision_weights: %{},
              # conjecture_activation_subject => [efficacy, ...] - the efficacies of tried courses of action to achieve a goal conjecture
              efficacies: %{},
              # conjecture_activation_subject => index of next course of action to try
              courses_of_action_indices: %{}
  end

  defmodule Round do
    @moduledoc "A round for a generative model. Also serves as episodic memory."

    defstruct started_on: nil,
              # timestamp of when the round was completed. Nil if on-going
              completed_on: nil,
              # names of sub-GMs that reported a completed round
              reported_in: [],
              # Uncontested predictions made by the GM and prediction errors from sub-GMs and detectors
              perceptions: [],
              # [prediction, ...] predictions reported by super-GMs about this GM's next beliefs
              received_predictions: [],
              # beliefs in this GM conjecture activations given perceptions (own predictions and prediction errors
              # from sub-GMs and detectors)
              beliefs: [],
              # [course_of_action, ...] - courses of action (to be) taken to achieve goals and/or shore up beliefs
              courses_of_action: [],
              # intents executed in the round
              intents: []

    def new() do
      %Round{started_on: now()}
    end

    def initial_round(gm_def) do
      %Round{Round.new() | beliefs: GenerativeModelDef.initial_beliefs(gm_def)}
    end
  end

  defmodule CourseOfAction do
    @moduledoc "A course of action is a sequence of named Intentions meant to be realized as Intents in an attempt
    to validate some activation of a conjecture"

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
  end

  defmodule Efficacy do
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
              # whether efficacy is for when a conjecture activation was believed (vs not) at the time of its execution
              when_already_believed?: false
  end

  @doc "Child spec as supervised worker"
  def child_spec(gm_def, super_gm_names, sub_gm_names) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [gm_def, super_gm_names, sub_gm_names]}
    }
  end

  @doc "Start the generative model"
  def start_link(gm_def, super_gm_names, sub_gm_names) do
    name = gm_def.name
    Logger.info("Starting Generative Model #{name}")

    %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices} =
      recall_experience(name)

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %State{
            gm_def: gm_def,
            rounds: [Round.initial_round(gm_def)],
            super_gm_names: super_gm_names,
            sub_gm_names: sub_gm_names,
            efficacies: efficacies,
            courses_of_action_indices: courses_of_action_indices
          }
          |> start_round()
        end,
        name: name
      )

    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  ### Event handling by the agent

  # Is this round timeout event meant for this GM? If so, complete the current round.
  def handle_event(
        {:round_timed_out, name},
        %State{
          gm_def: %GenerativeModelDef{
            name: name
          }
        } = state
      ) do
    # could be an obsolete round timeout event meant for a previous round that completed early
    if round_timed_out?(state) do
      complete_round(state)
    else
      state
    end
  end

  # Another GM completed a round - relevant is GM is sub-GM (a sub-believer that's also a GM)
  def handle_event(
        {:round_completed, name},
        %State{rounds: [%Round{reported_in: reported_in} = round | previous_rounds]} = state
      ) do
    if sub_gm?(name, state) do
      updated_round = %Round{round | reported_in: [name | reported_in]}

      %State{state | rounds: [updated_round | previous_rounds]}
      # Complete the round if it is fully informed
      |> maybe_complete_round()
    else
      state
    end
  end

  # A GM reported a prediction error (a belief not aligned with a received prediction) - add to perceptions if relevant
  def handle_event(
        {
          :prediction_error,
          %PredictionError{} = prediction_error
        },
        state
      ) do
    if prediction_error_relevant?(prediction_error, state) do
      add_prediction_error_to_round(prediction_error, state)
    else
      state
    end
  end

  # Another GM made a new prediction - receive it if from a super-GM
  def handle_event(
        {:prediction, %Prediction{source: gm_name} = prediction},
        %State{
          super_gm_names: super_gm_names,
          rounds: [%Round{received_predictions: received_predictions} = round | previous_rounds]
        } = state
      ) do
    if gm_name in super_gm_names do
      updated_round = %Round{round | received_predictions: [prediction | received_predictions]}
      %State{state | rounds: [updated_round | previous_rounds]}
    else
      state
    end
  end

  def handle_event(:shutdown, state) do
    shutdown(state)
  end

  # Ignore any other event
  def handle_event(_event, state) do
    state
  end

  ### PRIVATE

  # Recall what was remembered, if anything, after the last run
  defp recall_experience(gm_name) do
    case LongTermMemory.recall(gm_name, :experience) do
      nil ->
        %{efficacies: %{}, courses_of_action_indices: %{}}

      %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices} ->
        %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices}
    end
  end

  # Start the current round
  defp start_round(%State{gm_def: gm_def} = state) do
    PubSub.notify_after(
      {:round_timed_out, gm_name(state)},
      gm_def.max_round_duration
    )

    state
    # Carry over perceptions from previous round unless they've been carried over already too many times
    |> carry_over_perceptions()
    # Carry over received predictions from previous round unless they've been carried over already too many times
    |> carry_over_received_predictions()
    # Carry over the beliefs from the previous round
    |> carry_over_beliefs()
    # Activate conjectures
    |> activate_conjectures()
    # Remove carried-over perceptions mutually exclusive with the new conjecture activations
    |> remove_excluded_perceptions()
    # Make predictions about this round of perceptions given beliefs from previous round (possibly none)
    # Add them as new perceptions, possibly overriding carried-over perceptions
    |> make_predictions()
    # If there is no conjecture activation for this round, remove the carried-over beliefs and complete it right away
    |> check_if_inactive()
  end

  # Complete the current round if fully informed
  defp maybe_complete_round(state) do
    if round_ready_to_complete?(state) do
      complete_round(state)
    else
      state
    end
  end

  # Complete execution of the current round and set up the next round
  defp complete_round(%State{gm_def: gm_def} = state) do
    new_state =
      state
      # Update the precision weight assigned to each sub-GM/contributing detectors based on prediction errors
      #  about competing perceptions (their beliefs)
      |> update_precision_weights()
      # If there are different perception about the same thing, retain only the most trustworthy
      |> drop_least_trusted_competing_perceptions()
      # Compute the new beliefs in the GM's own conjectures,
      |> determine_beliefs()
      # For each prediction received, find if a new belief is a prediction error.
      # It is a maximal prediction error when no belief supports or contradicts a received prediction.
      # If a prediction error is generated, report it
      |> raise_prediction_errors()
      # Re-assess efficacies of courses of action taken in previous rounds given current beliefs
      # Have the CoAs caused the desired belief validations?
      |> update_efficacies()
      # Determine courses of action to achieve each non-yet-achieved goal, or to better validate a non-goal conjecture
      |> set_courses_of_action()
      # Execute the currently set courses of action
      |> execute_courses_of_action()
      # Terminate the current round (set completed_on, report round_completed)
      |> mark_round_completed()
      # Drop obsolete rounds (forget the distant past)
      |> drop_obsolete_rounds()
      # Add the next round
      |> add_new_round()

    PubSub.notify_after(
      {:round_timed_out, gm_def.name},
      gm_def.max_round_duration
    )

    new_state
  end

  defp gm_name(%State{gm_def: gm_def}) do
    gm_def.name
  end

  defp carry_over_perceptions(%State{rounds: [_round]} = state) do
    state
  end

  defp carry_over_perceptions(
         %State{
           rounds: [round, %Round{perceptions: prior_perceptions} = previous_round | other_rounds]
         } = state
       ) do
    carried_over_perceptions =
      Enum.reject(prior_perceptions, &(Perception.carry_overs(&1) > @max_carry_overs))
      |> Enum.map(&Perception.increment_carry_over(&1))

    updated_round = %Round{round | perceptions: carried_over_perceptions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  defp carry_over_received_predictions(%State{rounds: [_round]} = state) do
    state
  end

  defp carry_over_received_predictions(
         %State{
           rounds: [
             round,
             %Round{received_predictions: prior_received_predictions} = previous_round
             | other_rounds
           ]
         } = state
       ) do
    carried_over =
      Enum.reject(prior_received_predictions, &(Perception.carry_overs(&1) > @max_carry_overs))
      |> Enum.map(&Perception.increment_carry_over(&1))

    updated_round = %Round{round | received_predictions: carried_over}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  defp carry_over_beliefs(
         %State{
           rounds: [
             round,
             %Round{beliefs: prior_beliefs} = previous_round
             | other_rounds
           ]
         } = state
       ) do
    updated_round = %Round{round | beliefs: prior_beliefs}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  # Activate conjectures only if predictions were received in previous round (attention),
  # or the GM is a "hyper-prior".
  # If so, activate as many conjectures as possible that do not mutually exclude one another.
  # Goal conjecture activations win over other mutually exclusive activations.
  # If no activation, report immediately that the round has completed (it won't produce beliefs).
  defp activate_conjectures(
         %State{
           gm_def: gm_def,
           rounds:
             [%Round{received_predictions: received_predictions} | _previous_rounds] = rounds
         } = state
       ) do
    if GenerativeModelDef.hyper_prior?(gm_def) or Enum.count(received_predictions) > 0 do
      candidates_for_activation =
        Enum.map(gm_def.conjectures, & &1.activator.(&1, rounds))
        |> List.flatten()
        |> random_permutation()
        # Pull goals in front so they are the ones excluding others for being mutually exclusive
        |> Enum.sort(fn ca1, _ca2 -> ConjectureActivation.goal?(ca1) end)

      conjecture_activations =
        Enum.reduce(
          candidates_for_activation,
          [],
          fn candidate, acc ->
            if Enum.any?(
                 acc,
                 &ConjectureActivation.mutually_exclusive?(candidate, &1, gm_def.contradictions)
               ) do
              acc
            else
              [candidate | acc]
            end
          end
        )

      %State{state | conjecture_activations: conjecture_activations}
    else
      %State{state | conjecture_activations: []}
    end
  end

  # Remove perceptions that are mutually exclusive with the activated conjectures.
  # If a prediction: it was instantiated by a mutually exclusive conjecture
  # If a prediction error: it is an error about a prediction instantiated by a mutually exclusive conjecture
  defp remove_excluded_perceptions(
         %State{
           gm_def: gm_def,
           conjecture_activations: conjecture_activations,
           rounds: [
             %Round{perceptions: perceptions} = round
             | previous_rounds
           ]
         } = state
       ) do
    updated_perceptions =
      Enum.reject(
        perceptions,
        fn perception ->
          Enum.any?(
            conjecture_activations,
            fn %ConjectureActivation{conjecture: conjecture} ->
              GenerativeModelDef.mutually_exclusive?(
                gm_def,
                conjecture.name,
                Perception.prediction_conjecture_name(perception)
              )
            end
          )
        end
      )

    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp check_if_inactive(
         %State{conjecture_activations: conjecture_activations, rounds: [round | previous_rounds]} =
           state
       ) do
    # No point processing events if no conjecture was activated, go straight to round completion without beliefs
    if conjecture_activations == [] do
      updated_round = %Round{round | beliefs: []}

      %State{state | rounds: [updated_round | previous_rounds]}
      |> complete_round()
    else
      state
    end
  end

  # For each conjecture activations, make predictions about the GM's incoming perceptions.
  # Until contradicted, the predictions are perceptions of the GM
  # (I see what I expect to see unless my lying eyes tell me otherwise)
  defp make_predictions(
         %State{
           conjecture_activations: conjecture_activations,
           rounds: [%Round{perceptions: perceptions} = round | previous_rounds]
         } = state
       ) do
    predictions =
      conjecture_activations
      |> Enum.map(&make_predictions_from_conjecture(&1, state))
      |> List.flatten()

    # Add predictions to perceptions, removing prior perceptions that conflicted with the predictions
    updated_perceptions =
      Enum.reject(
        perceptions,
        fn perception ->
          Enum.any?(predictions, &Perception.same_subject?(perception, &1))
        end
      ) ++ predictions

    Enum.each(predictions, &PubSub.notify({:prediction, &1}))
    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp make_predictions_from_conjecture(
         %ConjectureActivation{conjecture: conjecture} = conjecture_activation,
         %State{rounds: rounds} = state
       ) do
    Enum.map(conjecture.predictors, & &1.(conjecture_activation, rounds))
    |> Enum.map(&%Prediction{&1 | source: gm_name(state)})
  end

  defp current_round(%State{rounds: [round | _]}) do
    round
  end

  defp sub_gm?(name, %State{sub_gm_names: sub_gm_names}) do
    name in sub_gm_names
  end

  defp round_timed_out?(%State{gm_def: gm_def} = state) do
    round = current_round(state)
    now() - round.started_on >= gm_def.max_round_duration
  end

  # This is a reported error to a prediction this GM made
  defp prediction_error_relevant?(
         %PredictionError{prediction: %Prediction{source: prediction_gm_name}},
         state
       ) do
    prediction_gm_name == gm_name(state)
  end

  # Add a prediction error to the perceptions (a mix of beliefs as predictions by this GM
  # and prediction errors from sub-GMs and detectors). Remove any created redundancies.
  defp add_prediction_error_to_round(
         %PredictionError{} = prediction_error,
         %State{rounds: [%Round{perceptions: perceptions} = round | previous_rounds]} = state
       ) do
    updated_perceptions = [
      prediction_error
      | Enum.reject(
          perceptions,
          &(Perception.prediction?(&1) and
              Perception.same_subject?(prediction_error, &1))
        )
    ]

    %State{state | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]}
  end

  # All considered GMs (precision weight > 0) have reported in
  defp round_ready_to_complete?(%State{sub_gm_names: sub_gm_names} = state) do
    %Round{reported_in: reported_in} = current_round(state)

    Enum.all?(
      sub_gm_names,
      &(not considered?(&1, state) or &1 in reported_in)
    )
  end

  # The sub-GM influences the GM
  defp considered?(sub_gm_name, %State{precision_weights: precision_weights}) do
    Map.get(precision_weights, sub_gm_name, 1.0) > 0
  end

  # Compute new beliefs from active conjectures given current state of the GM
  defp determine_beliefs(
         %State{conjecture_activations: conjecture_activations, rounds: [round | previous_rounds]} =
           state
       ) do
    beliefs =
      conjecture_activations
      |> Enum.map(&create_belief_from_conjecture(&1, state))

    %State{state | rounds: [%Round{round | beliefs: beliefs} | previous_rounds]}
  end

  defp create_belief_from_conjecture(
         %ConjectureActivation{
           conjecture: conjecture,
           about: about
         } = conjecture_activation,
         %State{rounds: rounds} = state
       ) do
    values_or_nil = conjecture.valuator.(conjecture_activation, rounds)

    Belief.new(
      source: gm_name(state),
      conjecture_name: conjecture.name,
      about: about,
      values: values_or_nil
    )
  end

  defp raise_prediction_errors(state) do
    %Round{beliefs: beliefs, received_predictions: predictions} = current_round(state)

    prediction_errors =
      Enum.reduce(
        predictions,
        [],
        fn %Prediction{conjecture_name: conjecture_name, about: about} = prediction, acc ->
          case Enum.find(beliefs, &(&1.conjecture_name == conjecture_name and &1.about == about)) do
            # If no belief matches the received prediction, then there's a "no predicted belief" prediction error
            nil ->
              prediction_error = %PredictionError{
                prediction: prediction,
                size: 1.0,
                belief:
                  Belief.new(
                    source: gm_name(state),
                    conjecture_name: conjecture_name,
                    about: about,
                    # nil -> not believed
                    values: nil
                  )
              }

              [prediction_error | acc]

            %Belief{values: values} = belief ->
              size = Prediction.prediction_error_size(prediction, values)

              if size > 0.0 do
                prediction_error = %PredictionError{
                  prediction: prediction,
                  size: size,
                  belief: belief
                }

                [prediction_error | acc]
              else
                acc
              end
          end
        end
      )

    Enum.each(prediction_errors, &PubSub.notify({:prediction_error, &1}))
    state
  end

  # Give more/less precision weight to competing contributors of prediction errors based on the respective
  # sizes of the errors (confirmation bias).
  # Temper by previous precision weight.
  defp update_precision_weights(%State{precision_weights: prior_precision_weights} = state) do
    %Round{perceptions: perceptions} = current_round(state)
    prediction_errors = Enum.filter(perceptions, &Perception.prediction_error?(&1))

    subjects =
      prediction_errors
      |> Enum.map(&{Perception.conjecture_name(&1), Perception.about(&1)})
      |> Enum.uniq()

    # The relative confidence levels in the sub-GMs and detectors (sources) who reported prediction errors,
    # given that they may report on the same subject (i.e. conjecture name and object of conjecture - about)
    # %{source_name => [confidence_level_re_subject, ...]}
    confidence_levels_per_source =
      Enum.reduce(
        subjects,
        %{},
        fn {conjecture_name, about}, acc ->
          # Find competing perceptions for the same conjecture (a GM has many conjectures, a detector is its own
          # conjecture) and object of the conjecture
          competing_prediction_errors =
            Enum.filter(
              prediction_errors,
              &(Perception.conjecture_name(&1) == conjecture_name and
                  Perception.about(&1) == about)
            )

          # Spread 1.0 worth of confidence among sources (GMs and detectors) reporting prediction errors about the same
          # The lesser the size of the error, the greater the confidence (confirmation bias)
          # subject [{source_name, confidence}, ...]
          relative_confidence_levels_per_subject =
            relative_confidence_levels(competing_prediction_errors)

          # Aggregate per source name the relative confidence levels per subject
          # %{source_name => [confidence_level_re_subject, ...]}
          Enum.reduce(
            relative_confidence_levels_per_subject,
            acc,
            fn {source_name, confidence_level}, acc1 ->
              Map.put(acc1, source_name, [confidence_level | Map.get(acc1, source_name, [])])
            end
          )
        end
      )

    updated_precision_weights =
      Enum.reduce(
        confidence_levels_per_source,
        prior_precision_weights,
        fn {source_name, levels}, acc ->
          average_confidence = Enum.sum(levels) / Enum.count(levels)

          updated_precision_weight_for_source =
            (Map.get(prior_precision_weights, source_name, 1.0) + average_confidence) / 2.0

          Map.put(acc, source_name, updated_precision_weight_for_source)
        end
      )

    %State{state | precision_weights: updated_precision_weights}
  end

  # No competition -> 1.0 (max) confidence in the source of a prediction error
  defp relative_confidence_levels([prediction_error]) do
    {Perception.source(prediction_error), 1.0}
  end

  # Spread 1.0 worth of confidence levels among sources with competing prediction errors about a same subject,
  # favoring the source reporting the least prediction error
  defp relative_confidence_levels(competing_prediction_errors) do
    # [{gm_name, confirmation_level}, ...]
    source_raw_levels =
      Enum.zip(
        Enum.map(competing_prediction_errors, &Prediction.source(&1)),
        Enum.map(
          competing_prediction_errors,
          # Confidence grows as prediction error decreases (confirmation bias)
          &(1.0 - &1.size)
        )
      )

    # Normalize the confidence levels among competing sources of beliefs to within 0.0 and 1.0, incl.
    levels_sum = source_raw_levels |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    Enum.map(
      source_raw_levels,
      fn {source_name, raw_level} ->
        {source_name, raw_level / levels_sum}
      end
    )
  end

  # When two perceptions are about the same thing, retain only the most trustworthy
  defp drop_least_trusted_competing_perceptions(
         %State{
           rounds: [
             %Round{perceptions: perceptions} = round | previous_rounds
           ]
         } = state
       ) do
    updated_perceptions =
      Enum.reduce(
        perceptions,
        {[], []},
        fn perception, {retained, considered} = _acc ->
          [most_trusted_one | others] =
            Enum.filter(perceptions, &Perception.same_subject?(&1, perception))
            |> Enum.sort(&(trust_in(&1, state) >= trust_in(&2, state)))

          if Enum.any?([most_trusted_one | others], &(&1 in retained or &1 in considered)) do
            {retained, Enum.uniq(considered ++ [most_trusted_one | others])}
          else
            {[most_trusted_one | retained], Enum.uniq(considered ++ [most_trusted_one | others])}
          end
        end
      )

    %State{state | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]}
  end

  # A GM fully trusts an uncorrected prediction
  def trust_in(%Prediction{}, _state) do
    1.0
  end

  # A GM trusts a prediction error proportionally to the precision weight it assigned to its source
  def trust_in(
        %PredictionError{} = prediction_error,
        %State{precision_weights: precision_weights}
      ) do
    Map.get(precision_weights, Perception.source(prediction_error), 1.0)
  end

  # Update the efficacies (measures of correlation) of all CoAs executed by this GM given the beliefs (and non-beliefs)
  # created in the current round.
  # A CoA's efficacy goes up with beliefs in the conjecture which caused the CoA (down if non-beliefs).
  # A belief validates its associated conjecture if parameters values are not nil.
  # The closer the belief follows the execution of a CoA meant to cause it, the higher the correlation.
  defp update_efficacies(
         %State{
           # %{conjecture_activation_subject: [efficacy, ...]}
           efficacies: efficacies
         } = state
       ) do
    %Round{beliefs: beliefs} = current_round(state)

    updated_efficacies =
      Enum.reduce(
        beliefs,
        efficacies,
        &update_efficacies_from_belief(&1, efficacies, state)
      )

    %State{state | efficacies: updated_efficacies}
  end

  # Update efficacies given a new belief
  defp update_efficacies_from_belief(
         %Belief{} = belief,
         efficacies,
         state
       ) do
    conjecture_believed? = Belief.believed?(belief)
    subject_of_belief = Belief.subject(belief)

    updated_conjecture_efficacies =
      Map.get(efficacies, subject_of_belief, [])
      |> revise_conjecture_efficacies(conjecture_believed?, state)

    Map.put(efficacies, subject_of_belief, updated_conjecture_efficacies)
  end

  # Revise the efficacies of various CoAs executed in all rounds to validate a conjecture as they correlate
  # to the current belief (or non-belief) in the conjecture.
  defp revise_conjecture_efficacies(conjecture_activation_efficacies, conjecture_believed?, state) do
    Enum.reduce(
      conjecture_activation_efficacies,
      [],
      fn %Efficacy{} = efficacy, acc ->
        updated_degree = update_efficacy_degree(efficacy, conjecture_believed?, state)

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
           when_already_believed?: when_already_believed?,
           degree: degree
         },
         conjecture_believed?,
         %State{
           rounds: rounds
         }
       ) do
    number_of_rounds = Enum.count(rounds)

    # Find the indices of rounds where the type of CoA was executed
    # and where what the conjecture was about (its subject) was already believed (or not)
    indices_of_rounds_with_coa =
      Enum.reduce(
        0..(number_of_rounds - 1),
        [],
        fn index, acc ->
          %Round{courses_of_action: courses_of_action, beliefs: beliefs} = Enum.at(rounds, index)

          if Enum.any?(
               courses_of_action,
               &(CourseOfAction.of_type?(&1, conjecture_activation_subject, intention_names) and
                   when_already_believed? ==
                     already_believed?(conjecture_activation_subject, beliefs))
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
    impact = if conjecture_believed?, do: 1.0, else: -1.0

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

  # Is (was) there among a set of given round beliefs, one asserting belief
  # in the subject of a given conjecture activation?
  defp already_believed?(conjecture_activation_subject, beliefs) do
    Enum.any?(
      beliefs,
      &(Belief.subject(&1) == conjecture_activation_subject and Belief.believed?(&1))
    )
  end

  # For each active conjecture, choose a CoA from the conjecture's CoA domain, favoring efficacy
  # and shortness. Only look at longer CoAs if efficacy of shorter CoAs disappoints.
  # Set no CoA for a goal that has been achieved (i.e. the goal activated conjecture is believed)
  # Set no CoA for a non-goal that is not believed (i.e. no belief to maintain)
  defp set_courses_of_action(
         %State{
           conjecture_activations: conjecture_activations,
           rounds: [round | previous_rounds],
           # conjecture_name => index of next course of action to try
           courses_of_action_indices: courses_of_action_indices,
           efficacies: efficacies
         } = state
       ) do
    {round_courses_of_action, updated_coa_indices, updated_efficacies} =
      Enum.reduce(
        conjecture_activations,
        [],
        fn conjecture_activation, acc ->
          cond do
            ConjectureActivation.goal?(conjecture_activation) ->
              if believed_now?(conjecture_activation, state) do
                acc
              else
                [select_course_of_action(conjecture_activation, state) | acc]
              end

            true ->
              if believed_now?(conjecture_activation, state) do
                [select_course_of_action(conjecture_activation, state) | acc]
              else
                acc
              end
          end
        end
      )
      # reducing [{selected_course_of_action, updated_coa_index, new_coa?}, ...]
      |> Enum.reduce(
        {[], courses_of_action_indices, efficacies},
        fn {%CourseOfAction{conjecture_activation: conjecture_activation} = course_of_action,
            maybe_updated_coa_index, new_coa?},
           {coas, indices, efficacies_acc} = _acc ->
          conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

          {
            Enum.uniq([course_of_action | coas]),
            Map.put(indices, conjecture_activation_subject, maybe_updated_coa_index),
            if(new_coa?,
              do: update_efficacies_with_new_coa(efficacies_acc, course_of_action, state),
              else: efficacies_acc
            )
          }
        end
      )

    updated_round = %Round{round | courses_of_action: round_courses_of_action}
    updated_courses_of_action_indices = Map.merge(courses_of_action_indices, updated_coa_indices)

    %State{
      state
      | courses_of_action_indices: updated_courses_of_action_indices,
        rounds: [updated_round | previous_rounds],
        efficacies: updated_efficacies
    }
  end

  defp believed_now?(conjecture_activation, state) do
    %Round{beliefs: beliefs} = current_round(state)

    Enum.any?(
      beliefs,
      &(ConjectureActivation.subject(conjecture_activation) == Belief.subject(&1) and
          Belief.believed?(&1))
    )
  end

  # Select a course of action for a conjecture
  # Returns {selected_course_of_action, updated_coa_index, new_coa?}
  defp select_course_of_action(
         %ConjectureActivation{} = conjecture_activation,
         %State{
           efficacies: efficacies,
           courses_of_action_indices: courses_of_action_indices
         } = state
       ) do
    conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

    # Create an untried CoA (shortest possible), give it a hypothetical efficacy (= average efficacy) and add it to the candidates
    coa_index = Map.get(courses_of_action_indices, conjecture_activation_subject, 0)

    untried_coa =
      new_course_of_action(
        conjecture_activation,
        coa_index
      )

    # Collect as candidates all tried CoAs for similar conjecture activations (same subject)
    # when belief in the conjecture was the same as now (believed vs not)
    # => [{CoA, degree_of_efficacy}, ...]
    believed? = believed_now?(conjecture_activation, state)

    tried =
      Map.get(efficacies, conjecture_activation_subject)
      |> Enum.filter(fn %Efficacy{when_already_believed?: when_already_believed?} ->
        when_already_believed? == believed?
      end)
      |> Enum.map(
        &{%CourseOfAction{
           conjecture_activation: conjecture_activation,
           intention_names: &1.intention_names
         }, &1.degree}
      )

    average_efficacy = average_efficacy(tried)

    # Candidates CoA are the previously tried CoAs plus a new one given the average efficacy of the other candidates.
    candidates =
      [{untried_coa, average_efficacy} | tried]
      # Normalize efficacies (sum = 1.0)
      |> normalize_efficacies()

    # Pick a CoA randomly, favoring higher efficacy
    course_of_action = pick_course_of_action(candidates)
    # Move the CoA index if we picked an untried CoA
    new_coa? = course_of_action == untried_coa
    updated_coa_index = if new_coa?, do: coa_index + 1, else: coa_index
    {course_of_action, updated_coa_index, new_coa?}
  end

  defp average_efficacy([]) do
    1.0
  end

  defp average_efficacy(tried) do
    (Enum.map(tried, &elem(&1, 1))
     |> Enum.sum()) / Enum.count(tried)
  end

  defp new_course_of_action(
         %ConjectureActivation{conjecture: %Conjecture{intention_domain: intention_domain}} =
           conjecture_activation,
         courses_of_action_index
       ) do
    # Convert the index into a list of indices e.g. 5 -> [1,1] , 5th CoA (0-based index) in an intention domain of 3 actions
    index_list =
      Integer.to_string(courses_of_action_index, Enum.count(intention_domain))
      |> String.to_charlist()
      |> Enum.map(&List.to_string([&1]))
      |> Enum.map(&String.to_integer(&1))

    intention_names =
      Enum.reduce(
        index_list,
        [],
        fn i, acc ->
          [Enum.at(intention_domain, i) | acc]
        end
      )
      |> Enum.reverse()

    %CourseOfAction{
      conjecture_activation: conjecture_activation,
      intention_names: intention_names
    }
  end

  # Return [{coa, efficacy}, ...] such that the sum of all efficacies == 1.0
  defp normalize_efficacies(candidate_courses_of_action) do
    sum =
      Enum.reduce(
        candidate_courses_of_action,
        0,
        fn {_cao, degree}, acc ->
          degree + acc
        end
      )

    Enum.reduce(
      candidate_courses_of_action,
      [],
      fn {cao, degree}, acc ->
        [{cao, degree / sum}, acc]
      end
    )
  end

  # Randomly pick a course of action with a probability proportional to its degree of efficacy
  defp pick_course_of_action([{coa, _degree}]) do
    coa
  end

  defp pick_course_of_action(candidate_courses_of_action) do
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
      "Ranges = #{inspect(ranges)} for courses of action #{candidate_courses_of_action}"
    )

    random = Enum.random(0..999) / 1000
    index = Enum.find(0..(Enum.count(ranges) - 1), &(random < Enum.at(ranges, &1)))
    {coa, _efficacy} = Enum.at(candidate_courses_of_action, index)
    coa
  end

  defp update_efficacies_with_new_coa(
         efficacies,
         %CourseOfAction{conjecture_activation: conjecture_activation},
         state
       ) do
    conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

    Map.put(
      efficacies,
      conjecture_activation_subject,
      [
        %Efficacy{
          conjecture_activation_subject: ConjectureActivation.subject(conjecture_activation),
          when_already_believed?: believed_now?(conjecture_activation, state),
          degree: 0
        }
        | Map.get(efficacies, conjecture_activation_subject, [])
      ]
    )
  end

  # Generate the intents to run the course of action.
  defp execute_courses_of_action(
         %State{gm_def: gm_def, rounds: [round | previous_rounds] = rounds} = state
       ) do
    %Round{courses_of_action: courses_of_action, beliefs: beliefs} = round

    updated_round =
      Enum.reduce(
        courses_of_action,
        round,
        fn %CourseOfAction{
             intention_names: intention_names,
             conjecture_activation: %ConjectureActivation{
               conjecture: %Conjecture{name: conjecture_name},
               about: about
             }
           },
           acc ->
          belief_values =
            case Enum.find(
                   beliefs,
                   &(&1.conjecture_name == conjecture_name and &1.about == about)
                 ) do
              nil ->
                nil

              %Belief{values: values} ->
                values
            end

          Enum.reduce(
            intention_names,
            acc,
            fn intention_name, %Round{intents: intents} = acc1 ->
              intention = GenerativeModelDef.intention(gm_def, intention_name)

              intent =
                Intent.new(
                  about: intention.intent_name,
                  value: intention.valuator.(belief_values)
                )

              if not (Intention.not_repeatable?(intention) and
                        would_be_repeated?(intent, rounds)) do
                PubSub.notify_intended(intent)
                %Round{acc1 | intents: [intent | intents]}
              else
                acc1
              end
            end
          )
        end
      )

    %State{state | rounds: [updated_round | previous_rounds]}
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

  defp mark_round_completed(%State{gm_def: gm_def, rounds: [round | previous_rounds]} = state) do
    PubSub.notify({:round_completed, gm_def.name})
    %State{state | rounds: [%Round{round | completed_on: now()} | previous_rounds]}
  end

  defp drop_obsolete_rounds(%State{rounds: rounds} = state) do
    %State{state | rounds: do_drop_obsolete_rounds(rounds)}
  end

  defp do_drop_obsolete_rounds([round | older_rounds] = rounds) do
    cutoff = now() - @forget_round_after_secs * 1000

    if round.completed_on > cutoff do
      [rounds | drop_obsolete_rounds(older_rounds)]
    else
      # every other round is also necessarily obsolete
      []
    end
  end

  defp add_new_round(%State{rounds: rounds} = state) do
    %State{state | rounds: [Round.new() | rounds]}
  end

  defp random_permutation([]) do
    []
  end

  defp random_permutation(list) do
    chosen = Enum.random(list)
    [chosen | random_permutation(List.delete(list, chosen))]
  end

  defp shutdown(%State{efficacies: efficacies, courses_of_action_indices: indices} = state) do
    LongTermMemory.store(
      gm_name(state),
      :experience,
      %{efficacies: efficacies, courses_of_action_indices: indices}
    )
  end
end
