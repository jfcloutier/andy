defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  # The lifecycle of a generative model (GM), after instantiation, is a sequence of time-boxed rounds during which the GM
  # both emits and receives events (predictions, prediction errors etc.)
  #
  # The GM keeps the final states of past rounds in memory so it can draw upon its recent past to make decisions in the current round.
  #
  # After a round is initialized, the GM handles events from other GMs as they also go, asynchronously, through their rounds.
  #
  # When the round completes, it starts a new round, after putting itself in "cold storage".

  # And so on, ad infinitum.
  #
  # Initializing the current round:
  #
  #           Setup a new round, carrying over unfinished business from the previous round, if any.
  #
  #           - Copy over all the perceptions from the previous round that have not already been copied too often
  #             (a GM's perceptions are prediction errors from sub-GMs and detectors,
  #             and predictions made by the GM that are not contradicted by prediction errors)
  #           - Carry over beliefs from the previous round, possibly overriding prior (default) beliefs of the new round
  #           - Carry over conjecture activation for non-achieved goals.
  #           - Activate self-activated conjectures
  #           - Remove carried-over perceptions that are attributable to conjectures that are mutually exclusive of this
  #             round's current conjecture activations
  #           - Make predictions about perceptions in this round from the initial conjecture activations, given carried-over
  #             beliefs and perceptions, and accordingly valuated. Add them to perceptions, replacing obsoleted perceptions.
  #           - Report (send out) these predictions
  #               - Sub-GMs with matching conjectures accumulate them as received predictions (may lead to them producing prediction errors)
  #               - Any detector that can directly verify a prediction is triggered
  #
  # Running the current round:
  #
  #           Handle events from other GMs this GM cares about until running the round times out or completes.
  #
  #           - Receive completed round notifications from sub-GMs; mark them as reported-in
  #             (i.e. they made their contributions to this round)
  #                 - Check if the round ready for completion (all considered sub-GMs reported in - with precision weight > 0).
  #                 - If so complete it right away.
  #           - Receive predictions from super-GMs and replace prior received predictions that are overridden
  #             (overridden if the have the same subject - conjecture name and object it is about -
  #             and are from the same GM).
  #           - For each received prediction, immediately
  #               - Activate the associated conjecture, unless prediction is redundant (conjecture already activated on same subject)
  #               - Remove current conjecture activations contradicted by the newly activated conjecture
  #               - Remove obsolete beliefs and perceptions (i.e. those derived from a removed conjecture activation)
  #               - Make predictions from the newly activated conjectures, if any
  #                 and start the round timeout clock if it had not yet been started
  #           - Receive prediction errors from sub-GMs and detectors as perceptions and replace overridden perceptions
  #             (a prediction error overrides the prediction the error contradicts)
  #               - After receiving a prediction error from a detector, see if all detectors activated by the GM
  #                 have reported a (possibly zero-sized) prediction error. If so, complete the round immediately.
  #
  # Completing the current round:
  #
  #           A round completes if no conjecture was activated, or all sub-GMs have reported in, or the round has timed out waiting to be completed.
  #           When completing a round, the GM updates its beliefs and carries out actions it estimates might be effective to achieve
  #           outstanding goals or shore up its updated beliefs.
  #
  #           - Update precision weighing of sub-GMs given prediction errors from competing sources of perceptions
  #               - Reduce precision weight of the competing sub-GMs that deviate more from a given prediction
  #                 (confirmation bias)
  #               - Increase precision weight of the sub-GMs that deviate the least or have no competitor
  #           - When two perceptions are about the same subject, retain only the more trustworthy
  #               - A GM retains one effective perception about something (e.g. can't perceive two distances to a wall)
  #           - Compute the round's final GM's beliefs for each activated conjecture given GM's present and past rounds,
  #             and determine if they are prediction errors (i.e. beliefs that contradict or are misaligned with
  #             received predictions).
  #           - The new beliefs replace any already held beliefs with the same subjects.
  #           - Report (send out) the prediction errors
  #           - Update course of action efficacies given current belief (i.e. re-evaluate what past courses of action
  #             seem to have worked best to achieve a belief or to maintain it)
  #           - Choose a course of action for each conjecture activation, influenced by historical efficacy,
  #               - to hopefully make belief in the activated conjecture true or keep it true in the next round
  #           - Execute the chosen courses of action by reporting valued intents from each one's sequence of intentions
  #               - Wait for a while until all executed intents have completed their actuation
  #           - Close the round
  #
  # Closing the current round
  #
  #           Do some housekeeping before moving on to the next round.
  #
  #           - Mark round completed and report completion
  #           - Drop obsolete rounds (those from a too distant past)
  #           - Add a round as the new current round
  #           - Initialize the new round (i.e. rinse and repeat)

  require Logger
  import Andy.Utils, only: [listen_to_events: 3, now: 0, delay_cast: 2]
  import Andy.GM.Utils, only: [info: 1, gm_name: 1, random_permutation: 1]
  alias Andy.Intent

  alias Andy.GM.{
    State,
    PubSub,
    GenerativeModelDef,
    Round,
    CourseOfAction,
    Belief,
    Conjecture,
    ConjectureActivation,
    Prediction,
    PredictionError,
    Perception,
    Efficacy,
    LongTermMemory,
    Detector
  }

  # How many rounds a perception/received prediction be carried over (short-term memory)
  @max_carry_overs 3

  @doc "Child spec as supervised worker"
  def child_spec([gm_def, super_gm_names, sub_gm_names]) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [gm_def, super_gm_names, sub_gm_names]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Start the generative model"
  def start_link(gm_def, super_gm_names, sub_gm_names) do
    name = gm_def.name

    Logger.info(
      "Starting Generative Model #{inspect(name)} with supers #{inspect(super_gm_names)} and subs #{
        inspect(sub_gm_names)
      }"
    )

    %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices} =
      recall_experience(name)

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %State{
            gm_def: gm_def,
            started: false,
            rounds: [Round.new(gm_def, 0)],
            super_gm_names: super_gm_names,
            sub_gm_names: sub_gm_names,
            efficacies: efficacies,
            courses_of_action_indices: courses_of_action_indices
          }
        end,
        name: name
      )

    listen_to_events(pid, __MODULE__, gm_def.name)
    {:ok, pid}
  end

  ### Event handling by the agent

  def handle_event(
        {:listening, __MODULE__, name},
        %State{} = state
      ) do
    if gm_name(state) == name do
      Logger.info("#{info(state)}: Listening to events")
      updated_state = state |> Round.round_status(:initializing)

      delay_cast(name, fn state -> initialize_round(state) end)
      %State{updated_state | started: true}
    else
      state
    end
  end

  # Is this round timeout event meant for this GM? If so, complete the current round.
  def handle_event(
        {:round_timed_out, name, round_id},
        %State{
          gm_def: %GenerativeModelDef{
            name: name
          },
          round_status: :running
        } = state
      ) do
    # could be an obsolete round timeout event meant for a previous round that completed early
    if Round.round_timed_out?(round_id, state) do
      Logger.info("#{info(state)}: Round timed out")
      updated_state = state |> Round.round_status(:completing)
      delay_cast(name, fn state -> complete_round(state) end)
      updated_state
    else
      Logger.info("#{info(state)}: Obsolete round timeout")
      state
    end
  end

  # Is this round execution timeout event meant for this GM? If so, close the current round.
  def handle_event(
        {:execution_timed_out, name, round_id},
        %State{
          gm_def: %GenerativeModelDef{
            name: name
          },
          round_status: :completing
        } = state
      ) do
    # could be an obsolete round timeout event meant for a previous round that completed early
    if Round.current_round?(round_id, state) do
      Logger.info("#{info(state)}: Round execution timed out")
      updated_state = state |> Round.round_status(:closing)
      delay_cast(name, fn state -> Round.close_round(state) |> add_new_round() end)
      updated_state
    else
      Logger.info("#{info(state)}: Obsolete round execution timeout")
      state
    end
  end

  # Another GM completed a round - relevant is GM is sub-GM (a sub-believer that's also a GM)
  def handle_event(
        {:round_completed, name},
        %State{
          started: true,
          round_status: :running,
          sub_gm_names: sub_gm_names,
          rounds: [%Round{reported_in: reported_in} = round | previous_rounds]
        } = state
      ) do
    if name in sub_gm_names do
      Logger.info("#{info(state)}: GM #{inspect(name)} reported in")
      updated_round = %Round{round | reported_in: [name | reported_in]}

      %State{state | rounds: [updated_round | previous_rounds]}
      # Complete the round if it is fully informed and has activated conjectures
      |> maybe_complete_round()
    else
      state
    end
  end

  # Another GM made a new prediction - receive it if relevant (from a super-GM and names a conjecture of this GM)
  # If not running the current round, buffer it to be replayed when the next round starts running.
  # Else start the round clock if not already started
  # 	Activate the applicable conjecture if not yet activated
  # 	Remove mutually excluded activations and their associated predictions made
  # 	Make predictions from the activated conjecture
  def handle_event(
        {:prediction, %Prediction{}} = event,
        %State{round_status: round_status} = state
      )
      when round_status != :running do
    buffer_event(state, event)
  end

  def handle_event(
        {:prediction, %Prediction{} = prediction},
        %State{round_status: :running} = state
      ) do
    if prediction_relevant?(prediction, state) do
      receive_prediction(state, prediction)
    else
      state
    end
  end

  def handle_event(
        {:prediction_error, %PredictionError{}} = event,
        %State{round_status: round_status} = state
      )
      when round_status != :running do
    buffer_event(state, event)
  end

  # A GM reported a prediction error (a belief not aligned with a received prediction) - add to perceptions if relevant
  def handle_event(
        {
          :prediction_error,
          %PredictionError{} = prediction_error
        },
        %State{
          round_status: :running
        } = state
      ) do
    if prediction_error_relevant?(prediction_error, state) do
      receive_prediction_error(state, prediction_error)
    else
      state
    end
  end

  def handle_event(
        {:actuated, intent} = event,
        %State{
          started: true,
          round_status: round_status
        } = state
      ) do
    if intent_relevant?(intent, state) do
      if round_status == :completing do
        receive_intent_actuated(state, intent)
      else
        Logger.info(
          "#{info(state)}: Ignoring actuated event #{inspect(event)} because round status is #{
            inspect(round_status)
          }"
        )

        state
      end
    else
      state
    end
  end

  def handle_event(:shutdown, state) do
    delay_cast(gm_name(state), fn state -> shutdown(state) end)
    %State{Round.round_status(state, :shutdown) | started: false}
  end

  # Ignore any other event
  def handle_event(event, state) do
    Logger.debug("#{info(state)}: Ignoring event #{inspect(event)}")
    state
  end

  ### PRIVATE

  # Initialize the new round which is already with prior (default) beliefs
  defp initialize_round(%State{gm_def: gm_def} = state) do
    Logger.info("#{info(state)}: Initializing new round")

    updated_state =
      state
      # Carry over perceptions from previous round unless they've been carried over already too many times
      |> carry_over_perceptions()
      # Carry over the beliefs from the previous round, possibly overriding the prior (i.e. default) beliefs
      |> carry_over_beliefs()
      # Carry over unachieved goal conjecture activations, activate self-activated conjectures
      |> initial_conjecture_activations()
      # Remove carried over perceptions and beliefs that are from conjectures mutually excluded from the current ones
      |> remove_excluded_perceptions_and_beliefs()
      # Make predictions, from activated conjectures, about this round of perceptions
      # given beliefs from previous round (possibly none)
      # Add them as new perceptions, possibly overriding carried-over perceptions
      |> make_predictions()
      |> Round.round_status(:running)

    %Round{id: round_id} = Round.current_round(updated_state)

    PubSub.notify_after(
      {:round_timed_out, gm_name(state), round_id},
      gm_def.max_round_duration
    )

    delay_cast(gm_name(state), fn state -> empty_event_buffer(state) end)
    updated_state
  end

  # Complete execution of the current round and set up the next round
  defp complete_round(%State{} = state) do
    Logger.info("#{info(state)}: Completing round")
    if state.conjecture_activations == [], do: Logger.warn("#{info(state)} Round completed without conjecture activations")
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
      # Tell ASAP parent GMs this GM has completed (even though it still has to execute CoAs if any)
      |> announce_completed()
      # Re-assess efficacies of courses of action taken in previous rounds given current beliefs
      # Have the CoAs caused the desired belief validations?
      |> update_efficacies()
      # Determine courses of action to achieve each non-yet-achieved goal, or to better validate an opinion (non-goal) conjecture
      |> set_courses_of_action()
      # Execute the currently set courses of action
      |> execute_courses_of_action()

    new_state
  end

  defp buffer_event(%State{event_buffer: event_buffer} = state, event) do
    %State{state | event_buffer: event_buffer ++ [event]}
  end

  defp announce_completed(state) do
    spawn(fn ->
      # Give time to the parents to process any prediction errors from this GM before they maybe complete
      Process.sleep(10)
      PubSub.notify({:round_completed, gm_name(state)})
    end)

    state
  end

  # Activate *not-yet activated* conjectures from the prediction
  defp activate_conjectures_from_prediction(
         %State{gm_def: gm_def, rounds: rounds, conjecture_activations: conjecture_activations} =
           state,
         %Prediction{conjecture_name: conjecture_name, about: prediction_about} = prediction
       ) do
    if Enum.any?(
         conjecture_activations,
         &(ConjectureActivation.subject(&1) == Perception.subject(prediction))
       ) do
      Logger.info("#{info(state)}: Conjecture already activated for #{inspect(prediction)}")
      []
    else
      conjecture = GenerativeModelDef.conjecture(gm_def, conjecture_name)

      conjecture.activator().(conjecture, rounds, prediction_about)
    end
  end

  # Recall what was remembered, if anything, after the last run
  defp recall_experience(gm_name) do
    Logger.info("#{inspect(gm_name)}: Recalling stored memory")

    case LongTermMemory.recall(gm_name, :experience) do
      nil ->
        %{efficacies: %{}, courses_of_action_indices: %{}}

      %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices} = recalled ->
        Logger.info("#{inspect(gm_name)}: Recalled #{inspect(recalled)}")
        %{efficacies: efficacies, courses_of_action_indices: courses_of_action_indices}
    end
  end

  defp empty_event_buffer(%State{event_buffer: event_buffer} = state) do
    Logger.info("#{info(state)}: Emptying event buffer #{inspect(event_buffer)}")

    updated_state =
      Enum.reduce(
        event_buffer,
        state,
        fn event, acc ->
          handle_event(event, acc)
          # Make sure the GM stays :running
          Round.round_status(acc, :running)
        end
      )
      |> Round.round_status(:running)

    %State{updated_state | event_buffer: []}
  end

  # Complete the current round if fully informed
  defp maybe_complete_round(
         %State{
           gm_def: gm_def,
           rounds: [
             %Round{started_on: started_on, early_timeout_on: early_timeout_on?, id: round_id} =
               current_round
             | previous_rounds
           ]
         } = state
       ) do
    if round_ready_to_complete?(state) do
      Logger.info("#{info(state)}: Round ready to complete")
      duration = now() - started_on
      min_round_duration = GenerativeModelDef.min_round_duration(gm_def)

      if duration < min_round_duration do
        if not early_timeout_on? do
          Logger.info("#{info(state)}: Too early to complete")

          PubSub.notify_after(
            {:round_timed_out, gm_name(state), round_id},
            min_round_duration - duration
          )

          updated_round = %Round{current_round | early_timeout_on: true}
          %State{state | rounds: [updated_round | previous_rounds]}
        else
          state
        end
      else
        updated_state = state |> Round.round_status(:completing)
        delay_cast(gm_name(state), fn state -> complete_round(state) end)
        updated_state
      end
    else
      Logger.info("#{info(state)}: Round not ready to complete")

      state
    end
  end

  defp add_new_round(%State{gm_def: gm_def, rounds: rounds} = state) do
    index = Round.next_round_index(rounds)

    updated_state =
      %State{state | rounds: [Round.new(gm_def, index) | rounds]}
      |> Round.round_status(:initializing)

    delay_cast(gm_name(state), fn state -> initialize_round(state) end)
    updated_state
  end

  defp intent_relevant?(%Intent{id: id}, state) do
    %Round{intents: intents} = Round.current_round(state)
    Enum.any?(intents, &(&1.id == id))
  end

  defp mark_intent_executed(
         %State{rounds: [%Round{intents: intents} = round | previous_rounds]} = state,
         %Intent{id: id} = intent
       ) do
    Logger.info("#{info(state)}: Marking intent #{inspect(intent)} executed")

    updated_intents =
      Enum.reduce(
        intents,
        [],
        fn %Intent{id: intent_id} = intent, acc ->
          if id == intent_id do
            [%Intent{intent | executed: true} | acc]
          else
            acc
          end
        end
      )

    updated_round = %Round{round | intents: updated_intents}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp maybe_close_round(state) do
    %Round{intents: intents} = Round.current_round(state)

    if Enum.all?(intents, &Intent.executed?(&1)) do
      updated_state = state |> Round.round_status(:closing)
      delay_cast(gm_name(state), fn state -> Round.close_round(state) |> add_new_round() end)
      updated_state
    else
      state
    end
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
      |> Enum.map(&Perception.increment_carry_overs(&1))

    Logger.info("#{info(state)}: Carrying over perceptions #{inspect(carried_over_perceptions)}")

    updated_round = %Round{round | perceptions: carried_over_perceptions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  defp carry_over_beliefs(%State{rounds: [_round]} = state), do: state

  # Add beliefs from previous round to the prior beliefs, possibly overriding them
  defp carry_over_beliefs(
         %State{
           rounds: [
             %Round{beliefs: prior_beliefs} = round,
             %Round{beliefs: previous_beliefs} = previous_round
             | other_rounds
           ]
         } = state
       ) do
    Logger.info("#{info(state)}: Carrying over all previous beliefs #{inspect(previous_beliefs)}")
    carried_over_beliefs = previous_beliefs |> Enum.map(&Belief.increment_carry_overs(&1))

    retained_prior_beliefs =
      Enum.reject(
        prior_beliefs,
        &Enum.any?(
          carried_over_beliefs,
          fn carried_over_belief ->
            Belief.subject(carried_over_belief) == Belief.subject(&1)
          end
        )
      )

    updated_round = %Round{round | beliefs: retained_prior_beliefs ++ carried_over_beliefs}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  # Keep unachieved goal conjecture activations if predictions were received in the previous round.
  # Otherwise, a goal conjecture activation lives until goal is achieved
  # or a mutually exclusive conjecture is self-activated or is activated via a prediction received in the round.
  # Activate self-activated conjectures
  # Keep the non-mutually exclusive conjecture activations.
  defp initial_conjecture_activations(
         %State{
           gm_def: gm_def,
           conjecture_activations: prior_conjecture_activations,
           rounds: rounds
         } = state
       ) do
    preserved_goal_activations =
      if predictions_previously_received?(state) do
        Enum.filter(
          prior_conjecture_activations,
          # ConjectureActivation.carry_overs(&1) <= @max_carry_overs and
          &(ConjectureActivation.goal?(&1) and
              not ConjectureActivation.achieved_now?(&1, state))
        )
        |> Enum.map(&ConjectureActivation.increment_carry_overs(&1))
      else
        Logger.info(
          "#{info(state)}: Dropping any prior goal activations because no previously received predictions"
        )

        []
      end

    Logger.info(
      "#{info(state)}: Preserving unachieved goal activations #{
        inspect(preserved_goal_activations)
      }"
    )

    # Get conjecture self-activations
    self_activations =
      Enum.filter(gm_def.conjectures, &Conjecture.self_activated?(&1))
      |> candidate_conjecture_activations(rounds)

    conjecture_activations =
      rationalize_conjecture_activations(
        self_activations ++ preserved_goal_activations,
        gm_def
      )

    Logger.info(
      "#{info(state)}: Initial conjecture activations #{inspect(conjecture_activations)}"
    )

    %State{state | conjecture_activations: conjecture_activations}
  end

  defp predictions_previously_received?(%State{rounds: [_round]}) do
    false
  end

  defp predictions_previously_received?(%State{rounds: [_round, previous_round | _others]}) do
    %Round{received_predictions: received_predictions} = previous_round
    Enum.count(received_predictions) > 0
  end

  defp candidate_conjecture_activations(conjectures, rounds, prediction_about \\ nil) do
    Enum.map(conjectures, & &1.activator.(&1, rounds, prediction_about))
    |> List.flatten()
    # Shuffle the candidates
    |> random_permutation()
    # Pull goals in front so they are the ones excluding others for being mutually exclusive
    |> Enum.sort(fn ca1, _ca2 -> ConjectureActivation.goal?(ca1) end)
  end

  defp rationalize_conjecture_activations(conjecture_activations, gm_def) do
    Enum.reduce(
      conjecture_activations,
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
  end

  # Remove perceptions and beliefs that are mutually exclusive with the activated conjectures.
  # If a prediction: it was instantiated by a mutually exclusive conjecture
  # If a prediction error: it is an error about a prediction instantiated by a mutually exclusive conjecture
  # If a belief: it is a belief about a mutually exclusive conjecture
  defp remove_excluded_perceptions_and_beliefs(
         %State{
           gm_def: gm_def,
           conjecture_activations: conjecture_activations,
           rounds: [
             %Round{perceptions: perceptions, beliefs: beliefs} = round
             | previous_rounds
           ]
         } = state
       ) do
    updated_perceptions =
      reject_mutually_excluded_perceptions(gm_def, perceptions, conjecture_activations)

    updated_beliefs = reject_mutually_excluded_beliefs(gm_def, beliefs, conjecture_activations)

    Logger.info(
      "#{info(state)}: After removing excluded perceptions: #{inspect(updated_perceptions)}"
    )

    Logger.info("#{info(state)}: After removing excluded beliefs: #{inspect(updated_beliefs)}")

    updated_round = %Round{round | perceptions: updated_perceptions, beliefs: updated_beliefs}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp reject_mutually_excluded_beliefs(gm_def, beliefs, conjecture_activations) do
    Enum.reject(
      beliefs,
      fn belief ->
        Enum.any?(
          conjecture_activations,
          fn conjecture_activation ->
            GenerativeModelDef.contradicts?(
              gm_def,
              ConjectureActivation.subject(conjecture_activation),
              Belief.subject(belief)
            )
          end
        )
      end
    )
  end

  defp reject_mutually_excluded_perceptions(gm_def, perceptions, conjecture_activations) do
    Enum.reject(
      perceptions,
      fn perception ->
        Enum.any?(
          conjecture_activations,
          fn conjecture_activation ->
            GenerativeModelDef.contradicts?(
              gm_def,
              ConjectureActivation.subject(conjecture_activation),
              Perception.subject(perception)
            )
          end
        )
      end
    )
  end

  defp receive_prediction(
         %State{
           gm_def: gm_def,
           conjecture_activations: conjecture_activations,
           rounds: [%Round{received_predictions: received_predictions} = round | previous_rounds]
         } = state,
         %Prediction{} = prediction
       ) do
    Logger.info("#{info(state)}: Received prediction #{inspect(prediction)}")

    updated_round = %Round{
      round
      | received_predictions: [
          prediction
          | Enum.reject(received_predictions, &Perception.same_subject?(&1, prediction))
        ]
    }

    updated_state = %State{state | rounds: [updated_round | previous_rounds]}

    # Activate associated conjectures
    case activate_conjectures_from_prediction(updated_state, prediction) do
      [] ->
        Logger.info(
          "#{info(state)}: No conjecture activations from receiving prediction #{
            inspect(prediction)
          }"
        )

        updated_state

      new_conjecture_activations ->
        # The new activations are added to prior ones minus priors that are mutually excluded
        updated_conjecture_activations =
          rationalize_conjecture_activations(
            new_conjecture_activations ++ conjecture_activations,
            gm_def
          )

        Logger.info(
          "#{info(state)}: Conjecture activations #{inspect(updated_conjecture_activations)} after receiving prediction #{
            inspect(prediction)
          }"
        )

        %State{updated_state | conjecture_activations: updated_conjecture_activations}
        |> remove_excluded_perceptions_and_beliefs()
        |> make_predictions(new_conjecture_activations)
    end
  end

  defp receive_prediction_error(
         %State{} = state,
         %PredictionError{size: size} = prediction_error
       ) do
    Logger.info("#{info(state)}: Received prediction error #{inspect(prediction_error)}")

    updated_state =
      if size > 0 do
        add_prediction_error_to_round(prediction_error, state)
      else
        state
      end

    # If from a detector, consider it reported in
    source = PredictionError.source(prediction_error)

    if Detector.detector_name?(source) do
      Logger.info("#{info(state)}: Detector #{inspect(source)} reported in")

      %State{rounds: [%Round{reported_in: reported_in} = round | previous_rounds]} = updated_state

      updated_round = %Round{round | reported_in: [source | reported_in]}

      %State{updated_state | rounds: [updated_round | previous_rounds]}
      # Complete the round if it is fully informed
      |> maybe_complete_round()
    else
      updated_state
    end
  end

  defp receive_intent_actuated(state, intent) do
    state
    |> mark_intent_executed(intent)
    |> maybe_close_round()
  end

  # Make predictions for all conjecture activations in the GM
  defp make_predictions(
         %State{
           conjecture_activations: conjecture_activations
         } = state
       ) do
    make_predictions(state, conjecture_activations)
  end

  # For each conjecture activations, make predictions about the GM's incoming perceptions.
  # Until contradicted, the predictions are perceptions of the GM
  # (I see what I expect to see unless my lying eyes tell me otherwise)
  defp make_predictions(
         %State{
           rounds: [
             %Round{perceptions: perceptions} = round | previous_rounds
           ]
         } = state,
         conjecture_activations
       ) do
    predictions =
      conjecture_activations
      |> Enum.map(&make_predictions_from_conjecture(&1, state))
      |> List.flatten()

    Logger.info("#{info(state)}: Made predictions #{inspect(predictions)}")

    # Add predictions to perceptions, removing prior perceptions that conflicted with the predictions
    updated_perceptions =
      Enum.reject(
        perceptions,
        fn perception ->
          Enum.any?(predictions, &Perception.same_subject?(perception, &1))
        end
      ) ++ predictions

    Logger.info("#{info(state)}: Updated perceptions to #{inspect(updated_perceptions)}")

    updated_state = %State{
      state
      | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]
    }

    Enum.each(predictions, &PubSub.notify({:prediction, &1}))

    updated_state
  end

  defp make_predictions_from_conjecture(
         %ConjectureActivation{conjecture: conjecture, goal: goal_or_nil} = conjecture_activation,
         %State{rounds: rounds} = state
       ) do
    Enum.map(conjecture.predictors, & &1.(conjecture_activation, rounds))
    |> Enum.reject(&(&1 == nil))
    |> Enum.map(&%Prediction{&1 | source: gm_name(state), goal: goal_or_nil})
  end

  # Can this prediction can be verified by this GM?
  defp prediction_relevant?(
         %Prediction{source: gm_name, conjecture_name: conjecture_name},
         %State{gm_def: gm_def, super_gm_names: super_gm_names}
       ) do
    gm_name in super_gm_names and GenerativeModelDef.has_conjecture?(gm_def, conjecture_name)
  end

  # Is this a reported error to a prediction this GM made?
  defp prediction_error_relevant?(
         %PredictionError{prediction: %Prediction{source: prediction_gm_name}},
         state
       ) do
    prediction_gm_name == gm_name(state)
  end

  # Add a prediction error to the perceptions if error > 0 and there's a matching
  # prediction in the perceptions. Remove any created redundancies.
  defp add_prediction_error_to_round(
         %PredictionError{} = prediction_error,
         %State{rounds: [%Round{perceptions: perceptions} = round | previous_rounds]} = state
       ) do
    Logger.info("#{info(state)}: Adding prediction error #{inspect(prediction_error)}")

    updated_perceptions = [
      prediction_error
      | Enum.reject(
          perceptions,
          &Perception.same_subject?(prediction_error, &1)
        )
    ]

    Logger.info("#{info(state)}: Updated perceptions #{inspect(updated_perceptions)}")
    %State{state | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]}
  end

  defp round_ready_to_complete?(%State{conjecture_activations: []} = state) do
    Logger.info("#{info(state)}: No conjecture activations. Round not ready to complete")
    false
  end

  defp round_ready_to_complete?(%State{sub_gm_names: sub_gm_names} = state) do
    %Round{reported_in: reported_in, perceptions: perceptions} = Round.current_round(state)

    sub_gms_reported_in?(sub_gm_names, reported_in, state) and
      activated_detectors_reported_in?(reported_in, perceptions, state)
  end

  defp sub_gms_reported_in?(sub_gm_names, reported_in, state) do
    Logger.info("#{info(state)}: Reported in #{inspect(reported_in)} ")

    Enum.all?(
      sub_gm_names,
      &(not_considered?(&1, state) or &1 in reported_in)
    )
  end

  defp activated_detectors_reported_in?(reported_in, perceptions, state) do
    activated_detectors = activated_detectors(perceptions)
    Logger.info("#{info(state)}: Activated detectors #{inspect(activated_detectors)} ")

    Enum.all?(
      activated_detectors,
      fn detector_pattern ->
        Enum.any?(
          reported_in,
          &(Detector.detector_name?(&1) and Detector.name_matches_pattern?(&1, detector_pattern))
        )
      end
    )
  end

  defp activated_detectors(perceptions) do
    Enum.filter(
      perceptions,
      fn perception ->
        carry_overs = Perception.carry_overs(perception)
        conjecture_name = Perception.prediction_conjecture_name(perception)
        carry_overs == 0 and Detector.detector_name?(conjecture_name)
      end
    )
    |> Enum.map(&Perception.prediction_conjecture_name(&1))
  end

  # The sub-GM influences the GM
  defp not_considered?(sub_gm_name, %State{precision_weights: precision_weights} = state) do
    not_considered? = Map.get(precision_weights, sub_gm_name, 1.0) == 0

    if not_considered?,
      do: Logger.info("#{info(state)}: Not considering sub-GM #{inspect(sub_gm_name)}")

    not_considered?
  end

  # Compute new beliefs from active conjectures given current state of the GM
  # to add to and possibly override already held beliefs of same subject
  defp determine_beliefs(
         %State{
           conjecture_activations: conjecture_activations,
           rounds: [%Round{beliefs: current_beliefs} = round | previous_rounds]
         } = state
       ) do
    new_beliefs =
      conjecture_activations
      |> Enum.map(&create_belief_from_conjecture(&1, state))

    Logger.info("#{info(state)}: New beliefs #{inspect(new_beliefs)}")

    remaining_current_beliefs =
      Enum.reject(
        current_beliefs,
        fn current_belief ->
          Enum.any?(new_beliefs, &(Belief.subject(&1) == Belief.subject(current_belief)))
        end
      )

    beliefs = remaining_current_beliefs ++ new_beliefs
    Logger.info("#{info(state)}: Final beliefs #{inspect(beliefs)}")

    %State{state | rounds: [%Round{round | beliefs: beliefs} | previous_rounds]}
  end

  defp create_belief_from_conjecture(
         %ConjectureActivation{
           conjecture: conjecture,
           about: about,
           goal: goal_or_nil
         } = conjecture_activation,
         %State{rounds: rounds} = state
       ) do
    values_or_nil = conjecture.valuator.(conjecture_activation, rounds)

    Belief.new(
      source: gm_name(state),
      conjecture_name: conjecture.name,
      about: about,
      goal: goal_or_nil,
      values: values_or_nil
    )
  end

  defp raise_prediction_errors(state) do
    Logger.info("#{info(state)}: Raising prediction errors")
    %Round{beliefs: beliefs, received_predictions: predictions} = Round.current_round(state)

    prediction_errors =
      Enum.reduce(
        predictions,
        [],
        fn %Prediction{conjecture_name: conjecture_name, about: about} = prediction, acc ->
          case Enum.find(beliefs, &(&1.conjecture_name == conjecture_name and &1.about == about)) do
            # If no belief matches the subject of the received prediction, then there's no prediction error (just don't know)
            nil ->
              Logger.info(
                "#{info(state)}: No prediction error. No belief matches prediction #{
                  inspect(prediction)
                }."
              )

              acc

            %Belief{values: values} = belief ->
              size = Prediction.prediction_error_size(prediction, values)

              if size > 0.0 do
                prediction_error = %PredictionError{
                  prediction: prediction,
                  size: size,
                  belief: belief
                }

                Logger.info(
                  "#{info(state)}: Prediction error of #{size} - Mismatch between belief #{
                    inspect(belief)
                  } and prediction #{inspect(prediction)}"
                )

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
    Logger.info("#{info(state)}: Updating precision weighing")
    %Round{perceptions: perceptions} = Round.current_round(state)
    prediction_errors = Enum.filter(perceptions, &Perception.prediction_error?(&1))

    subjects =
      prediction_errors
      |> Enum.map(&Perception.subject(&1))
      |> Enum.uniq()

    # The relative confidence levels in the sub-GMs and detectors (sources) who reported prediction errors,
    # given that they may report on the same subject (i.e. conjecture name and object of conjecture - about)
    # %{source_name => [confidence_level_re_some_subject, ...]}
    confidence_levels_per_source =
      Enum.reduce(
        subjects,
        %{},
        fn subject, acc ->
          # Find competing perceptions for the same conjecture (a GM has many conjectures, a detector is its own
          # conjecture) and object of the conjecture
          competing_prediction_errors =
            Enum.filter(
              prediction_errors,
              &Perception.has_subject?(&1, subject)
            )

          if Enum.count(competing_prediction_errors) > 1 do
            Logger.info(
              "#{info(state)}: Competing prediction errors on subject #{inspect(subject)}:  #{
                inspect(competing_prediction_errors)
              }"
            )
          end

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

    Logger.info("#{info(state)}: Updated precision weights #{inspect(updated_precision_weights)}")

    %State{state | precision_weights: updated_precision_weights}
  end

  # No competition -> 1.0 (max) confidence in the source of a prediction error
  defp relative_confidence_levels([prediction_error]) do
    [{Perception.source(prediction_error), 1.0}]
  end

  # Spread 1.0 worth of confidence levels among sources with competing prediction errors about a same subject,
  # favoring the source reporting the least prediction error
  defp relative_confidence_levels(competing_prediction_errors) do
    # [{gm_name, confirmation_level}, ...]
    source_raw_levels =
      Enum.zip(
        Enum.map(competing_prediction_errors, &PredictionError.source(&1)),
        Enum.map(
          competing_prediction_errors,
          # Confidence grows as prediction error decreases (confirmation bias)
          &(1.0 - &1.size)
        )
      )

    # Normalize the confidence levels among competing sources of beliefs to within 0.0 and 1.0, incl.
    levels_sum = source_raw_levels |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if levels_sum == 0 do
      source_raw_levels
    else
      Enum.map(
        source_raw_levels,
        fn {source_name, raw_level} ->
          {source_name, raw_level / levels_sum}
        end
      )
    end
  end

  # When two perceptions are about the same thing, retain only the most trustworthy
  defp drop_least_trusted_competing_perceptions(
         %State{
           rounds: [
             %Round{perceptions: perceptions} = round | previous_rounds
           ]
         } = state
       ) do
    Logger.info("#{info(state)}: Dropping least trusted competing perceptions")

    {updated_perceptions, _} =
      Enum.reduce(
        perceptions,
        {[], []},
        fn perception, {retained, considered} = _acc ->
          [most_trusted_one | others] =
            Enum.filter(perceptions, &Perception.same_subject?(&1, perception))
            |> Enum.sort(&(gain(&1, state) >= gain(&2, state)))

          if Enum.any?([most_trusted_one | others], &(&1 in retained or &1 in considered)) do
            {retained, Enum.uniq(considered ++ [most_trusted_one | others])}
          else
            {[most_trusted_one | retained], Enum.uniq(considered ++ [most_trusted_one | others])}
          end
        end
      )

    dropped = perceptions -- updated_perceptions
    Logger.info("#{info(state)}: Dropped perceptions #{inspect(dropped)}")
    %State{state | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]}
  end

  # A GM fully trusts an uncorrected prediction: maximum gain
  defp gain(%Prediction{}, _state) do
    1.0
  end

  # A GM assigns gain to a prediction error proportionally to the precision weight it assigned to its source
  defp gain(
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
    %Round{beliefs: beliefs} = Round.current_round(state)

    Logger.info(
      "#{info(state)}: Updating efficacies #{inspect(efficacies)} from beliefs #{inspect(beliefs)}"
    )

    updated_efficacies =
      Enum.reduce(
        beliefs,
        efficacies,
        &Efficacy.update_efficacies_from_belief(&1, &2, state)
      )

    Logger.info("#{info(state)}: Updated efficacies #{inspect(updated_efficacies)}")
    %State{state | efficacies: updated_efficacies}
  end

  # For each active conjecture, choose a CoA from the conjecture's CoA domain, favoring efficacy
  # and shortness. Only look at longer CoAs if efficacy of shorter CoAs disappoints.
  # Set no CoA for a goal that has been achieved (i.e. the goal activated conjecture is achieved)
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
    Logger.info("#{info(state)}: Setting CoAs for #{inspect(conjecture_activations)}")

    coa_selections = CourseOfAction.possible_courses_of_actions(conjecture_activations, state)

    Logger.info("#{info(state)}: CoA selections #{inspect(coa_selections)}")
    # reducing [{selected_course_of_action, updated_coa_index, new_coa?}, ...]
    {round_courses_of_action, updated_coa_indices, updated_efficacies} =
      Enum.reduce(
        coa_selections,
        {[], courses_of_action_indices, efficacies},
        fn {%CourseOfAction{conjecture_activation: conjecture_activation} = course_of_action,
            maybe_updated_coa_index, new_coa?},
           {coas, indices, efficacies_acc} = _acc ->
          conjecture_activation_subject = ConjectureActivation.subject(conjecture_activation)

          {
            Enum.uniq([course_of_action | coas]),
            Map.put(indices, conjecture_activation_subject, maybe_updated_coa_index),
            if(new_coa?,
              do:
                Efficacy.update_efficacies_with_new_coa(efficacies_acc, course_of_action, state),
              else: efficacies_acc
            )
          }
        end
      )

    Logger.info(
      "#{info(state)}: CoAs set to #{inspect(round_courses_of_action)} with updated CoA indices #{
        inspect(updated_coa_indices)
      } and updated efficacies #{inspect(updated_efficacies)}"
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

  # Generate the intents to run the course of action.
  defp execute_courses_of_action(
         %State{gm_def: gm_def, rounds: [round | previous_rounds]} = state
       ) do
    %Round{courses_of_action: courses_of_action, beliefs: beliefs} = round

    Logger.info("#{info(state)}: Executing CoAs #{inspect(courses_of_action)} ")

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
           } = coa,
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

          Logger.info("#{info(state)}: Executing CoA #{inspect(coa)} ")

          Enum.reduce(
            intention_names,
            acc,
            fn intention_name, %Round{} = acc1 ->
              intentions = GenerativeModelDef.intentions(gm_def, intention_name)

              CourseOfAction.execute_intentions(
                intentions,
                belief_values,
                [acc1 | previous_rounds],
                state
              )
            end
          )
        end
      )

    updated_state = %State{state | rounds: [updated_round | previous_rounds]}

    if Round.has_intents?(updated_round) do
      # Allow for the intents to be actuated
      time_out_in = round(1000 * Round.intents_duration(updated_round) + 50)

      Logger.info(
        "#{info(state)}: Setting execution timeout for round #{round.id} in #{time_out_in} msecs"
      )

      PubSub.notify_after(
        {:execution_timed_out, gm_name(state), round.id},
        time_out_in
      )

      updated_state
    else
      Logger.info("#{info(state)}: No intents in round. Closing now.")
      updated_state |> Round.round_status(:closing)
      delay_cast(gm_name(state), fn state -> Round.close_round(state) |> add_new_round() end)
      updated_state
    end
  end

  defp shutdown(%State{efficacies: efficacies, courses_of_action_indices: indices} = state) do
    Logger.info("#{info(state)}: Storing experience")

    LongTermMemory.store(
      gm_name(state),
      :experience,
      %{efficacies: efficacies, courses_of_action_indices: indices}
    )

    state
  end
end
