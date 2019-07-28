defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  # TODO
  #      - courses_of_action: [CourseOfAction, ...]
  #      - PredictionError has Belief: predictor, size, belief
  #      - Prediction has source (gm_name)
  #      - Perception :: Prediction | PredictionError

  # Round start:
  #           - Start timer on round timeout
  #           - Copy over all the perceptions from the previous round
  #             (prediction errors from sub-GMs and detectors
  #             and predictions made by GM not contradicted by prediction errors)
  #           - Copy over all the received predictions from the previous round
  #           - Activate conjectures (as goals or not, avoiding mutual exclusions)
  #             given previous received predictions and perceptions
  #           - If no conjecture activations, communicate that the round has (prematurely) completed
  #           - Drop copied perceptions and received predictions that are about inactive conjectures
  # During round:
  #           - Receive inactive round notifications from sub-GMs; mark them reported-in
  #                 - Check if round ready for completion (all attended-to sub-GMs reported in). If so complete it.
  #           - Receive predictions from super-GMs and replace overridden previous predictions
  #           - Receive prediction errors as perceptions and replaces any perceptions they override if they
  #             in response to a prediction made by the GM
  #           - Receive round completion notifications from sub-GMs; mark them reported-in
  #                 - Check if round ready for completion (all attended-to sub-GMs reported in). If so complete it.
  # Round completion (all sub-gms have reported in or the round has timed out):
  #           - Update attention paid to sub-GMs given prediction errors from competing sources of perceptions
  #               - Reduce attention to the competing sub-GMs that deviate more from a given prediction (confirmation bias)
  #               - Increase attention to the sub-GMs that deviate the least or have no competitor
  #           - When two perceptions are about the same thing, retain only the more trustworthy
  #               - A GM retains one effective perception about something
  #                (e.g. can't perceive two distances to a wall)
  #           - Compute the GM's beliefs for each activated conjecture given GM's present and past rounds,
  #             and determine if they are prediction errors (i.e. contradict or are misaligned with received predictions)
  #           - Communicate the prediction errors
  #           - Make predictions about forthcoming perceptions, given conjecture activations and previous perceptions
  #           - Communicate predictions
  #               - Sub-GMs accumulate received predictions (may lead to them producing prediction errors)
  #               - Any detectors that could directly verify a prediction is triggered
  #           - Update course of action efficacies given current beliefs
  #             (re-evaluate what courses of action seem to work best)
  #           - Choose courses of action to
  #               - promote beliefs in activated, goal conjectures,
  #               - confirm held beliefs in, activated, non-goal conjectures
  #           - Execute the chosen courses of action
  #           - Mark round completed and communicate completion
  #           - Drop obsolete rounds
  #           - Add new round and start it

  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.Intent
  alias Andy.GM.{PubSub, GenerativeModelDef, Belief, Conjecture,
                 ConjectureActivation, Prediction, PredictionError,
                 Perception}

  # for how long rounds are remembered
  @forget_round_after_secs 60

  defmodule State do
    defstruct gm_def: nil,
              # a GenerativeModelDef - static
              # Names of the generative models this GM feeds into according to the GM graph
              super_gm_names: [],
              # Names of the generative models that feed into this GM according to the GM graph
              sub_gm_names: [],
              # latest rounds of activation of the generative model
              rounds: [],
              # conjecture_name => [efficacy, ...] - the efficacies of tried courses of action to achieve a goal conjecture
              efficacies: %{},
              # conjecture_name => index of next course of action to try
              courses_of_action_indices: %{}
  end

  defmodule Round do
    @moduledoc "A round for a generative model"

    defstruct started_on: nil,
              # timestamp of when the round was completed. Nil if on-going
              completed_on: nil,
              # attention currently given to sub-GMs and detectors => float from 0 to 1 (complete attention)
              attention: %{},
              # Conjecture activations, some of which can be goals. One conjecture can lead to multiple activations.
              conjecture_activations: [],
              # names of sub-believer GMs that reported a completed round
              reported_in: [],
              # Uncontested predictions made by the GM and prediction errors from sub-GMs and detectors
              perceptions: [],
              # [prediction, ...] predictions communicated by super-GMs about this GM's beliefs
              received_predictions: [],
              # beliefs in this GM conjecture activations given perceptions
              beliefs: [],
              # [course_of_action, ...] - courses of action (to be) taken to achieve goals or shore up beliefs
              courses_of_action: []

    def new() do
      %Round{started_on: now()}
    end

    def initial_round(gm_def) do
      %Round{Round.new() | beliefs: GenerativeModelDef.initial_beliefs(gm_def)}
    end

    end

  defmodule CourseOfAction do
    @moduledoc "A course of action is a sequence of Intents meant to be realized in an attempt to validate
    some activation of a named conjecture"

    defstruct conjecture_name: nil,
              intents: []

  end

  defmodule Efficacy do
    @moduledoc "The historical efficacy of a course of action to validate a conjecture as a goal.Efficacy is
    gauged by the proximity of the CoA to a later round that achieves the goal, tempered by any prior efficacy
    measurement."

    defstruct degree: 0,
              # degree of efficacy, float from 0 to 1.0
              # [intention.name, ...] a course of action
              course_of_action: []
  end

  @doc "Child spec as supervised worker"
  def child_spec(gm_def, super_gm_names, sub_gm_names) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [gm_def, super_gm_names, sub_gm_names]}
    }
  end

  @doc "Start the memory server"
  def start_link(gm_def, super_gm_names, sub_gm_names) do
    name = gm_def.name
    Logger.info("Starting Generative Model #{name}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %State{
            gm_def: gm_def,
            rounds: [Round.initial_round(gm_def)],
            super_gm_names: super_gm_names,
            sub_gm_names: sub_gm_names
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
    if sub_generative_model?(name, state) do
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
        %State{rounds: [round | previous_rounds]} = state
      ) do
    if prediction_error_relevant?(prediction_error, state) do
      updated_round = add_prediction_error_to_round(round, prediction_error)
      %State{state | rounds: [updated_round | previous_rounds]}
    else
      state
    end
  end

  # Another GM made a new prediction - receive it if from a super-GM
  def handle_event(
        {:prediction, %Belief{source: gm_name} = prediction},
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

  # Ignore any other event
  def handle_event(_event, state) do
    state
  end

  ### PRIVATE

  # Start the current round
  defp start_round(%State{gm_def: gm_def} = state) do
    PubSub.notify_after(
      {:round_timed_out, name(state)},
      gm_def.max_round_duration
    )

    state
    |> carry_over_perceptions()
    |> carry_over_received_predictions()
    |> activate_conjectures()
    |> drop_irrelevant_perceptions()
    |> drop_irrelevant_received_predictions()
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
      # Update the attention paid to each sub-GM/contributing detectors based on prediction errors
      #  about competing perceptions (their beliefs)
      |> update_attention()
      # If there are different perception about the same thing, retain only the most trustworthy
      |> drop_least_trusted_perceptions()
      # Compute beliefs in the GM's own conjectures,
      |> determine_beliefs()
      # For each prediction received, find if a new belief is a prediction error.
      # If so, communicate it
      |> raise_prediction_errors()
      # Make predictions about next round of perceptions given new beliefs
      |> make_predictions()
        # Re-assess efficacies of courses of action taken in previous rounds given current beliefs
      # Have the CoAs caused the desired belief validations?
      |> update_efficacies()
      # Determine courses of action to achieve each non-yet-achieved goal, or to better validate a non-goal conjecture
      |> set_courses_of_action()
      # Execute the currently set courses of action
      |> execute_courses_of_action()
      # Terminate the current round (set completed_on, communicate round_completed)
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

  defp name(%State{gm_def: gm_def}) do
    gm_def.name
  end

  defp carry_over_perceptions(%State{rounds: [_round]} = state) do
    state
  end

  defp carry_over_perceptions(
         %State{rounds: [round, %Round{perceptions: prior_perceptions} = previous_round | other_rounds]} =
           state
       ) do
    updated_round = %Round{round | perceptions: prior_perceptions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  defp carry_over_received_predictions(%State{rounds: [_round]} = state) do
    state
  end

  defp carry_over_received_predictions(
         %State{
           rounds: [
             round,
             %Round{received_predictions: predictions} = previous_round | other_rounds
           ]
         } = state
       ) do
    updated_round = %Round{round | received_predictions: predictions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  # Activate as many GM conjectures as possible that do not mutually exclude one another.
  # If no activation, notify immediately that the round has completed (it won't produce beliefs).
  defp activate_conjectures(
         %State{
           gm_def: gm_def,
           rounds: [round | previous_rounds]
         } = state
       ) do
    candidate_activations =
      Enum.map(gm_def.conjectures, & &1.activator.(state))
      |> List.flatten()
      |> random_permutation()

    conjecture_activations =
      Enum.reduce(
        candidate_activations,
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

    if conjecture_activations == [] do
      PubSub.notify({:round_completed, gm_def.name})
    end

    updated_round = %Round{round | conjecture_activations: conjecture_activations}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_irrelevant_perceptions(%State{
         rounds: [
           %Round{
             conjecture_activations: conjecture_activations,
             perceptions: perceptions
           } = round
           | previous_rounds
         ]
       } = state) do
    updated_perceptions = drop_obsolete(perceptions, conjecture_activations)
    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_irrelevant_received_predictions(%State{
         rounds: [
           %Round{
             conjecture_activations: conjecture_activations,
             received_predictions: predictions
           } = round
           | previous_rounds
         ]
       } = state) do
    updated_predictions = drop_obsolete(predictions, conjecture_activations)
    updated_round = %Round{round | received_predictions: updated_predictions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_obsolete(perceptions, conjecture_activations) do
    Enum.reject(
      perceptions,
      fn perception ->
        not Enum.any?(
            conjecture_activations,
            &(&1.conjecture_name == Perception.name(perception) and &1.about == Perception.about(perception))
          )
      end
    )
  end

  defp make_predictions(
         %State{rounds: [%Round{perceptions: perceptions} = round | previous_rounds]} = state
       ) do
    predictions =
      conjecture_activations(state)
      |> Enum.map(&make_predictions_from_conjecture(&1, state))
      |> List.flatten()

      # Add predictions to perceptions, removing prior perceptions that conflicted with the predictions
      updated_perceptions = Enum.reject(perceptions,
        fn(perception) ->
        Enum.any?(predictions, &(Perception.competing?(perception, &1)))
      end) ++ predictions
    Enum.each(predictions, &PubSub.notify({:prediction, &1}))
    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp make_predictions_from_conjecture(
         %ConjectureActivation{conjecture_name: conjecture_name} = conjecture_activation,
         %State{gm_def: gm_def} = state
       ) do
    conjecture = GenerativeModelDef.conjecture(gm_def, conjecture_name)

    Enum.map(conjecture.predictors, & &1.(conjecture_activation, state))
    |> Enum.map(&%Prediction{&1 | source: name(state)})
  end

  defp current_round(%State{rounds: [round | _]}) do
    round
  end

  defp sub_generative_model?(name, %State{sub_gm_names: sub_gm_names}) do
    name in sub_gm_names
  end

  defp round_timed_out?(%State{gm_def: gm_def} = state) do
    round = current_round(state)
    now() - round.started_on >= gm_def.max_round_duration
  end

  defp prediction_error_relevant?(
         %PredictionError{predictor: predictor_gm_name},
         state
       ) do
    predictor_gm_name == name(state)
  end

  # Add a prediction error to the perceptions (a mix of beliefs as predictions by this GM
  # and prediction errors from sub-GMs and detectors). Remove any created redundancies.
  defp add_prediction_error_to_round(
         %Round{perceptions: perceptions} = round,
         %PredictionError{belief: belief, size: size} = prediction_error
       ) do
    updated_perceptions = [
      prediction_error
      | Enum.reject(
          perceptions,
          &prediction_error_replaces_prediction?(prediction_error, &1)
        )
    ]

    %Round{round | perceptions: updated_perceptions}
  end

  defp prediction_error_replaces_prediction?(
         %PredictionError{} = prediction_error,
         %Prediction{} = prediction
       ) do
    Perception.competing?(prediction_error, prediction)
  end

  defp prediction_error_replaces_prediction?(%PredictionError{} = _prediction_error, _) do
    false
  end


  # All attended-to GMs have reported in
  defp round_ready_to_complete?(%State{sub_gm_names: sub_gm_names} = state) do
    %Round{reported_in: reported_in} = current_round(state)

    Enum.all?(
      sub_gm_names,
      &(not attended_to?(&1, state) or &1 in reported_in)
    )
  end

  # The believer has the attention of the GM
  defp attended_to?(believer_spec, state) do
    Map.get(attention(state), believer_spec, 1.0) > 0
  end

  defp attention(state) do
    %Round{attention: attention} = current_round(state)
    attention
  end

  # Compute beliefs in active conjectures given current state of the GM
  defp determine_beliefs(%State{rounds: [round | previous_rounds]} = state) do
    beliefs =
      conjecture_activations(state)
      |> Enum.map(&create_belief(&1, state))

    %State{state | rounds: [%Round{round | beliefs: beliefs} | previous_rounds]}
  end

  defp create_belief(
         %ConjectureActivation{
           conjecture_name: conjecture_name,
           about: about,
           param_domains: param_domains
         } = conjecture_activation,
         %State{} = state
       ) do
    conjecture = activated_conjecture(conjecture_activation, state)
    parameter_values = conjecture.validator.(about, param_domains, state)

    Belief.new(
      source: name(state),
      name: conjecture_name,
      about: about,
      parameter_values: parameter_values
    )
  end

  defp raise_prediction_errors(state) do
    %Round{beliefs: beliefs, received_predictions: predictions} = current_round(state)
    prediction_errors =
      Enum.reduce(
        predictions,
        [],
        fn %Prediction{source: source, name: name, about: about} = prediction, acc ->
          case Enum.find(beliefs, &(&1.name == name and &1.about == about)) do
            nil ->
              acc

            belief ->
              size = prediction_error_size(belief, prediction)

              if size > 0.0 do
                prediction_error = %PredictionError{predictor: source, size: size, belief: belief}
                [prediction_error | acc]
              else
                acc
              end
          end
        end
      )

    Enum.each(prediction_errors, &PubSub.notify({:prediction_error, &1}))
  end

  defp activated_conjectures(state) do
    conjecture_activations(state)
    |> Enum.map(&activated_conjecture(&1, state))
  end

  # Get the current conjecture activations
  defp conjecture_activations(state) do
    %Round{conjecture_activations: conjecture_activations} = current_round(state)
    conjecture_activations
  end

  # Get the conjecture for a conjecture activation
  defp activated_conjecture(%ConjectureActivation{conjecture_name: conjecture_name}, %State{
         gm_def: gm_def
       }) do
    Enum.find(gm_def.conjectures, &(&1.name == conjecture_name))
  end

  defp prediction_error_size(%Belief{parameter_values: parameter_values},
         %Prediction{parameter_sub_domains: parameter_sub_domains}) do
         compute_prediction_error_size(parameter_values, parameter_sub_domains)
  end

  defp compute_prediction_error_size(nil, _parameter_sub_domains) do
    1.0
  end

  defp compute_prediction_error_size(parameter_values, parameter_sub_domains) do
    value_errors =
      Enum.reduce(
        parameter_values,
        [],
        fn {param_name, param_value}, acc ->
          param_sub_domain = Map.get(parameter_sub_domains, param_name)
          value_error = compute_value_error(param_value, param_sub_domain)
          [value_error | acc]
        end
      )

    # Retain the maximum value error
    Enum.reduce(value_errors, 0, &max(&1, &2))
  end

  defp compute_value_error(_value, sub_domain) when sub_domain in [nil, []] do
    0
  end

  # Assuming a normal distribution over the parameter domain
  defp compute_value_error(value, low..high = _range) when is_number(value) do
    mean = (low + high) / 2
    std = (high - low) / 4
    delta = abs(mean - value)

    cond do
      delta <= std ->
        0

      delta <= std * 1.5 ->
        0.25

      delta <= std * 2 ->
        0.5

      delta <= std * 3 ->
        0.75

      true ->
        1.0
    end
  end

  defp compute_value_error(value, list) when is_list(list) do
    if value in list do
      0
    else
      1
    end
  end

  # Give more/less attention to competing contributors of perceptions as prediction errors based on the respective
  # sizes of the errors.
  # Temper by previous attention level.
  defp update_attention(%State{rounds: [%Round{perceptions: perceptions} = round | previous_rounds]} = state) do
    prior_attention = previous_attention(state)
    # [{conjecture_name, object_of_conjecture}, ...]
    prediction_errors = Enum.filter(perceptions, &(Perception.prediction_error?(&1)))
    subjects =
      prediction_errors
      |> Enum.map(&({Perception.name(&1), Perception.about(&1)}))
      |> Enum.uniq()

    # The relative confidence levels in the sub-GMs who reported prediction errors, given that they may report
    # on the same subject (i.e. conjecture and object of conjecture)
    # %{sub_gm_name => [confidence_level_re_subject, ...]}
    confidence_levels_per_sub_gm =
      Enum.reduce(
        subjects,
        %{},
        fn {conjecture_name, about}, acc ->
          # Find competing perceptions for the same conjecture and object of the conjecture
          competing_prediction_errors =
            Enum.filter(
              prediction_errors,
              &(Perception.name(&1) == conjecture_name and Perception.about(&1) == about)
            )

          # Spread 1.0 worth of confidence among sources reporting prediction errors about the same subject
          # [{gm_name, confidence}, ...]
          relative_confidence_levels_per_subject =
            relative_confidence_levels(competing_prediction_errors)

          # Aggregate per source names the relative confidence levels per subject with those for other subjects
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

    updated_attention =
      Enum.reduce(
        confidence_levels_per_sub_gm,
        prior_attention,
        fn {sub_gm_name, levels}, acc ->
          average_confidence = Enum.sum(levels) / Enum.count(levels)

          updated_attention_for_gm =
            (Map.get(prior_attention, sub_gm_name, 1.0) + average_confidence) / 2.0

          Map.put(acc, sub_gm_name, updated_attention_for_gm)
        end
      )

    updated_round = %Round{round | attention: updated_attention}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp previous_attention(%State{rounds: [_round]}) do
    %{}
  end

  defp previous_attention(%State{
         rounds: [_round, %Round{attention: attention} = _previous_round | _]
       }) do
    attention
  end

  # No competition -> 1.0 (max) confidence in the source of a prediction error
  defp relative_confidence_levels([prediction_error]) do
    {Perception.source(prediction_error), 1.0}
  end

  # Spread 1.0 worth of confidence levels among sources with competing prediction errors about a same subject,
  # favoring the source reporting the least controversial prediction error
  defp relative_confidence_levels(competing_prediction_errors) do
    # [{gm_name, confirmation_level}, ...]
    source_raw_levels =
      Enum.zip(
        Enum.map(competing_prediction_errors, &(Prediction.source(&1))),
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
  defp drop_least_trusted_perceptions(
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
          [one | others] =
            Enum.filter(perceptions, &Perception.competing?(&1, perception))
            |> Enum.sort(&(trust_in(&1, state) >= trust_in(&2, state)))

          if Enum.any?([one | others], &(&1 in retained or &1 in considered)) do
            {retained, Enum.uniq(considered ++ [one | others])}
          else
            {[one | retained], Enum.uniq(considered ++ [one | others])}
          end
        end
      )

    %State{state | rounds: [%Round{round | perceptions: updated_perceptions} | previous_rounds]}
  end

  # A GM fully trusts an uncorrected prediction
  def trust_in(%Prediction{}, _state) do
    1.0
  end

  # A GM trusts a prediction error proportionally to the attention given to its source
  def trust_in(
        %PredictionError{} = prediction_error,
        %State{} = state
      ) do
    %Round{attention: attention} = current_round(state)
    Map.get(attention, Perception.source(prediction_error), 1.0)
  end

  # A CoA's efficacy goes up when correlated to realized beliefs (levels > 0.5) from the same conjecture that prompted it.
  # The closer the validated belief follows the execution of a CoA meant to validate it, the higher the correlation
  defp update_efficacies(
         %State{
           # %{conjecture_name: [efficacy, ...]}
           efficacies: efficacies,
           rounds: [round | _previous_rounds] = rounds
         } = state
       ) do
    updated_efficacies =
      Enum.reduce(
        round.beliefs,
        efficacies,
        &update_efficacies_from_belief(&1, efficacies, rounds)
      )

    %State{state | efficacies: updated_efficacies}
  end

  # TODO - No more belief levels
  # Update efficacies given a new belief
  defp update_efficacies_from_belief(
         %Belief{
           # conjecture name
           name: name,
           level: level
         },
         efficacies,
         rounds
       ) do
    updated_conjecture_efficacies =
      Map.get(efficacies, name)
      |> revise_conjecture_efficacies(level, rounds)

    Map.put(efficacies, about, updated_conjecture_efficacies)
  end

  # Revise the efficacies of CoAs executed in all rounds and prompted by a conjecture about the new belief, given its level.
  defp revise_conjecture_efficacies(conjecture_efficacies, new_belief_level, rounds) do
    Enum.reduce(
      conjecture_efficacies,
      [],
      fn %Efficacy{course_of_action: course_of_action, degree: degree} = efficacy, acc ->
        updated_degree =
          update_efficacy_degree(course_of_action, new_belief_level, degree, rounds)

        [%Efficacy{efficacy | degree: updated_degree} | acc]
      end
    )
  end

  # Update the degree of efficacy of a CoA in achieving the current belief level
  # across all (remembered) rounds where it was executed
  defp update_efficacy_degree(course_of_action, belief_level, degree, rounds) do
    number_of_rounds = Enum.count(rounds)

    indices_of_rounds_with_coa =
      Enum.reduce(
        0..(number_of_rounds - 1),
        [],
        fn index, acc ->
          %Round{courses_of_action: courses_of_action} = Enum.at(rounds, index)
          if course_of_action in courses_of_action, do: [index | acc], else: acc
        end
      )
      |> Enum.reverse()

    number_of_rounds_with_coa = Enum.count(indices_of_rounds_with_coa)

    impacts_on_belief =
      Enum.reduce(
        indices_of_rounds_with_coa,
        [],
        fn round_index, acc ->
          closeness = number_of_rounds - round_index
          # e.g. 4/3, 1/3
          round_factor = closeness / number_of_rounds_with_coa
          [round_factor | acc]
        end
      )
      |> normalize_values()

    # Use the maximum impact on belief by an CoA from this round or a previous round
    max_impact = Enum.max(impacts_on_belief, fn -> 0 end)
    current_degree = belief_level * max_impact

    # Give equal weight to the latest and prior degrees of efficacy of a CoA on validating a belief
    current_degree + degree / 2.0
  end

  # For each active conjecture, choose a CoA from the conjecture's CoA domain favoring effectiveness
  # and shortness, looking at longer CoAs only if effectiveness of shorter CoAs disappoints.
  defp set_courses_of_action(
         %State{
           rounds: [round | previous_rounds],
           courses_of_action_indices: courses_of_action_indices
         } = state
       ) do
    {courses_of_action, updated_indices} =
      Enum.map(
        activated_conjectures(state),
        &select_course_of_action(&1, state)
      )
      |> Enum.reduce(
        {%{}, courses_of_action_indices},
        fn {conjecture_name, course_of_action, updated_coa_index}, {coas, indices} = _acc ->
          {
            Map.put(coas, conjecture_name, course_of_action),
            Map.put(indices, conjecture_name, updated_coa_index)
          }
        end
      )

    # one course of action per active conjecture name
    updated_round = %Round{round | courses_of_action: courses_of_action}

    %State{
      state
      | courses_of_action_indices: Map.merge(courses_of_action_indices, updated_indices),
        rounds: [updated_round | previous_rounds]
    }
  end

  # Select a course of action for a conjecture
  defp select_course_of_action(
         conjecture,
         %State{
           gm_def: gm_def,
           efficacies: efficacies,
           courses_of_action_indices: courses_of_action_indices
         }
       ) do
    # Create an untried CoA (shortest possible), give it a hypothetical efficacy (= average efficacy) and add it to the candidates
    coa_index = Map.get(courses_of_action_indices, conjecture.name, 0)

    untried_coa =
      new_course_of_action(
        conjecture,
        coa_index
      )

    # Collect all tried CoAs for the conjecture as candidates as [{CoA, efficacy}, ...]
    tried =
      Map.get(efficacies, conjecture.name)
      |> Enum.map(&{&1.course_of_action, &1.degree})

    average_efficacy = average_efficacy(tried)

    candidates =
      [{untried_coa, average_efficacy} | tried]
      # Normalize efficacies (sum = 1.0)
      |> normalize_efficacies()

    # Pick a CoA randomly, favoring higher efficacy
    course_of_action = pick_course_of_action(candidates)
    # Move the CoA index if we picked an untried CoA
    updated_coa_index = if course_of_action == untried_coa, do: coa_index + 1, else: coa_index
    {conjecture.name, course_of_action, updated_coa_index}
  end

  defp average_efficacy([]) do
    1.0
  end

  defp average_efficacy(tried) do
    (Enum.map(tried, &elem(&1, 1))
     |> Enum.sum()) / Enum.count(tried)
  end

  defp new_course_of_action(
         %Conjecture{intention_domain: intention_domain},
         courses_of_action_index
       ) do
    # Convert the index into a list of indices e.g. 4 -> [1,1] , 5th CoA (0-based index) in an intention domain of 3 actions
    index_list =
      Integer.to_string(courses_of_action_index, Enum.count(intention_domain))
      |> String.to_charlist()
      |> Enum.map(&List.to_string([&1]))
      |> Enum.map(&String.to_integer(&1))

    Enum.reduce(
      index_list,
      [],
      fn i, acc ->
        [Enum.at(intention_domain, i) | acc]
      end
    )
    |> Enum.reverse()
  end

  # Return [{coa, efficacy}, ...] such that the sum of all efficacies == 1.0
  defp normalize_efficacies(candidate_courses_of_action) do
    sum =
      Enum.reduce(
        candidate_courses_of_action,
        0,
        fn {_cao, efficacy}, acc ->
          efficacy + acc
        end
      )

    Enum.reduce(
      candidate_courses_of_action,
      [],
      fn {cao, efficacy}, acc ->
        [{cao, efficacy / sum}, acc]
      end
    )
  end

  defp normalize_values(values) do
    sum = Enum.sum(values)

    Enum.reduce(values, 0, &(&1 / sum + &2))
    |> Enum.reverse()
  end

  # Randomly pick a course of action with a probability proportional to its efficacy
  defp pick_course_of_action([{coa, _efficacy}]) do
    coa
  end

  defp pick_course_of_action(candidate_courses_of_action) do
    {ranges_reversed, _} =
      Enum.reduce(
        candidate_courses_of_action,
        {[], 0},
        fn {_coa, efficacy}, {ranges_acc, top_acc} ->
          {[top_acc + efficacy | ranges_acc], top_acc + efficacy}
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

  # Generate the intents to run the course of action. Don't repeat the same intention.
  defp execute_courses_of_action(state) do
    %Round{courses_of_action: courses_of_action} = current_round(state)

    Enum.reduce(
      courses_of_action,
      [],
      fn {_conjecture_name, intentions}, executed ->
        new_intentions = Enum.reject(intentions, &(&1.intent_name in executed))

        Enum.each(
          new_intentions,
          &PubSub.notify_intended(
            Intent.new(
              about: &1.intent_name,
              value: &1.valuator.(state)
            )
          )
        )

        Enum.map(new_intentions, & &1.intent_name) ++ executed
      end
    )

    state
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

  defp set_goals(%State{gm_def: gm_def} = state) do
    goals =
      Enum.filter(gm_def.conjectures, & &1.motivator.(state))
      |> Enum.map(& &1.name)

    %State{state | goals: goals}
  end

  # Conjecture is believed by default in the initial round
  defp conjecture_was_believed?(_conjecture_activation, %State{rounds: [_round]}) do
    true
  end

  # Was the conjecture believed in the previous round?
  defp conjecture_was_believed?(
         %ConjectureActivation{conjecture_name: conjecture_name},
         %State{rounds: [_round, previous_round | _]}
       ) do
    Enum.any?(previous_round.beliefs, &(&1.about == conjecture_name and &1.level >= 0.5))
  end

  defp random_permutation([]) do
    []
  end

  defp random_permutation(list) do
    chosen = Enum.random(list)
    [chosen | random_permutation(List.delete(list, chosen))]
  end
end