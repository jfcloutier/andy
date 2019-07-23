defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  # TODO - Conjecture ->* ConjectureActivation
  #      - ConjectureActivation, Belief and Prediction have (conjecture_)name and about
  #      - PubSub of {:prediction_error, belief}
  #      - prediction by GM as default perception (until contradicted by prediction error)
  #      - courses_of_action: [CourseOfAction, ...]

  # TODO - Round start:
  #           - Start timer on round timeout
  #           - Copy over all the perceptions from the previous round (predictions made by GM and prediction errors from sub-believers)
  #           - Copy over all the received predictions from the previous round
  #           - Activate conjectures (as goals or not, avoiding mutual exclusions) given previous received predictions and perceptions
  #           - If no activated conjecture (instantiating conjecture activations), communicate that the round is inactive
  #           - Drop copied perceptions and received predictions that are about inactive conjectures
  #           - Make predictions about forthcoming perceptions (beliefs by sub-believers), given conjecture activations and previous perceptions
  #           - Communicate predictions to sub-believers
  # TODO - During round:
  #           - Receive inactive round notifications from sub-believers; mark them reported-in
  #                 - Check if round ready for completion (all attended-to sub-believers reported in). If so complete it.
  #           - Receive predictions from super-GMs and replace overridden previous predictions
  #           - Receive prediction errors from sub-believers and replace the perceptions they override
  #           - Receive round completion notifications from sub-believers.
  #                 - Check if round ready for completion (all attended-to sub-believers reported in). If so complete it.
  # TODO - Round completion (all sub-believers have reported in or the round has timed out):
  #           - Update attention paid to sub-believers given prediction errors from competing sources of perceptions
  #           - Set the belief levels of perceptions from attention and prediction errors
  #           - Compute the GM's beliefs for each activated conjecture, given prediction errors on perceptions and received predictions.
  #           - Communicate prediction errors (beliefs of the GM that differ from received predictions)
  #           - Update course of action efficacies given current beliefs (re-evaluate what courses of action seem to work best)
  #           - Choose and execute courses of action to
  #               - believe in activated, goal conjectures,
  #               - keep believing in believed, activated, non-goal conjectures
  #           - Drop obsolete rounds
  #           - Mark round completed and communicate completion
  #           - Add new round and start it


  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.Intent
  alias Andy.GM.{PubSub, GenerativeModelDef, Belief, Conjecture, ConjectureActivation}
  @behaviour Andy.GM.Believer

  @forget_round_after_secs 60 # for how long rounds are remembered

  defmodule State do
    defstruct gm_def: nil,
                # a GenerativeModelDef - static
                # Specs of Believers that feed into this GM according to the GM graph
              sub_believers: [],
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
                # attention currently given to sub-believers - believer_spec => float from 0 to 1 (complete attention)
              attention: %{},
                # Conjecture activations, some of which can be goals. One conjecture can lead to multiple activations.
              conjecture_activations: [],
                # names of sub-believer GMs that reported a completed round
              reported_in: [],
                # [belief, ...] - perceptions are error-free predictions made by this GM (converted to beliefs)
                # or prediction errors reported by sub-believers (their mis-predicted or unpredicted beliefs)
              perceptions: [],
                # [prediction, ...] predictions communicated by super-GMs about this GM's beliefs
              received_predictions: [],
                # beliefs in this GM conjecture activations given perceptions
              beliefs: [],
                # [course_of_action, ...] - courses of action taken to achieve goals or shore up beliefs
              courses_of_action: []

    def new() do
      %Round{started_on: now()}
    end

    def initial_round(gm_def) do
      %Round{Round.new() | beliefs: GenerativeModelDef.initial_beliefs(gm_def)}
    end

  end

  defmodule CourseOfAction do
    @moduledoc "A course of action is a series of Intents meant to validate a named conjecture"

    defstruct conjecture_name: nil,
              intents: []
  end

  defmodule Efficacy do
    @moduledoc """
    The historical efficacy of a course of action to validate a conjecture as a goal.
    Efficacy is gauged by the proximity of the CoA to a future round that achieves the goal,
    tempered by any prior efficacy measurement.
    """

    defstruct degree: 0,
                # degree of efficacy, float from 0 to 1.0
              course_of_action: [] # [intention.name, ...] a course of action
  end

  @doc "Child spec as supervised worker"
  def child_spec(gm_def, sub_believer_specs) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [gm_def, sub_believer_specs]}
    }
  end

  @doc "Start the memory server"
  def start_link(gm_def, sub_believer_specs) do
    name = gm_def.name
    Logger.info("Starting Generative Model #{name}")
    {:ok, pid} = Agent.start_link(
      fn () ->
        %State{
          gm_def: gm_def,
          rounds: [Round.initial_round(gm_def)],
          sub_believers: sub_believer_specs
        }
        |> start_round()
      end,
      [name: name]
    )
    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  ### Event handling by the agent

  def handle_event(
        {:round_timed_out, name},
        %State{gm_def: gm_def} = state
      ) do
    if name == gm_def.name do
      if round_timed_out?(
           state
         ) do # could be an obsolete round timeout event meant for a previous round that completed early
        new_state = complete_round(state)
        PubSub.notify_after(
          {:round_timed_out, name},
          gm_def.max_round_duration
        )
        new_state
      else
        state
      end
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
    else
      state
    end
  end

  # Another GM reported a new belief - relevant if GM is sub-believer
  def handle_event(
        {
          :prediction_error,
          belief
        },
        %State{gm_def: gm_def, rounds: [round | previous_rounds]} = state
      ) do
    if belief_relevant?(belief, state) do
      updated_round = add_prediction_error_to_round(round, belief)
      updated_state = %State{state | rounds: [updated_round | previous_rounds]}
      if round_ready_to_complete?(updated_state) do
        completed_state = complete_round(updated_state)
        PubSub.notify_after(
          {:round_timed_out, gm_def.name},
          gm_def.max_round_duration
        )
        completed_state
      else
        updated_state
      end
    else
      state
    end
  end

  # Another GM made a new prediction - relevant if from a super-GM
  def handle_event(
        {:prediction, prediction, target_gms},
        %State{gm_def: gm_def, rounds: [round | previous_rounds]} = state
      ) do
    if gm_def.name in target_gms do
      updated_round = %Round{round | received_predictions: [prediction | round.predictions]}
      %State{state | rounds: [updated_round | previous_rounds]}
    else
      state
    end
  end

  # Ignore any other event
  def handle_event(_event, state) do
    state
  end

  ### Believer

  def something_or_other() do
    # TODO
    []
  end

  ### PRIVATE
  
  # Start the current round
  defp start_round(%State{} = state) do
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
    |> make_predictions()
  end

  defp name(%State{gm_def: gm_def}) do
    gm_def.name
  end

  defp carry_over_perceptions(%State{rounds: [round]} = state) do
    state
  end

  defp carry_over_perceptions(
         %State{rounds: [round, %Round{perceptions: perceptions} = previous_round | other_rounds]} = state
       ) do
    updated_round = %Round{round | perceptions: perceptions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  defp carry_over_received_predictions(%State{rounds: [round]} = state) do
    state
  end

  defp carry_over_received_predictions(
         %State{rounds: [round, %Round{received_predictions: predictions} = previous_round | other_rounds]} = state
       ) do
    updated_round = %Round{round | received_predictions: predictions}
    %State{state | rounds: [updated_round, previous_round | other_rounds]}
  end

  # Activate as many GM conjectures as possible that do not mutually exclude one another.
  defp activate_conjectures(
         %State{
           gm_def: gm_def,
           rounds: [round | previous_rounds]
         } = state
       ) do
    candidate_activations = Enum.map(gm_def.conjectures, &(&1.activator.(state)))
                            |> List.flatten()
                            |> random_permutation()
    conjecture_activations = Enum.reduce(
      candidate_activations,
      [],
      fn (candidate, acc) ->
        if Enum.any?(acc, &(ConjectureActivation.mutually_exclusive?(candidate, &1, gm_def.contradictions))) do
          acc
        else
          [candidate | acc]
        end
      end
    )
    updated_round = %Round{round | conjecture_activations: conjecture_activations}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_irrelevant_perceptions(
         %State{
           rounds: [%Round{
                      conjecture_activations: conjecture_activations,
                      perceptions: perceptions
                    } = round | previous_rounds]
         }
       ) do
    updated_perceptions = drop_obsolete_beliefs(perceptions, conjecture_activations)
    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_irrelevant_received_predictions(
         %State{
           rounds: [%Round{
                      conjecture_activations: conjecture_activations,
                      received_predictions: predictions
                    } = round | previous_rounds]
         }
       ) do
    updated_predictions = drop_obsolete_beliefs(predictions, conjecture_activations)
    updated_round = %Round{round | received_predictions: updated_predictions}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp drop_obsolete_beliefs(beliefs, conjecture_activations) do
    Enum.reject(
      beliefs,
      fn (%Belief{name: name, about: about} = belief) ->
        Belief.from_generative_model?(belief) and
        not Enum.any?(conjecture_activations, &(&1.conjecture_name == name and &1.about == about))
      end
    )
  end

  defp make_predictions(%State{sub_believers: sub_believers} = state) do
    activated_conjectures(state)
    |> Enum.map(&(make_conjecture_predictions(&1, state)))
    |> List.flatten()
    |> Enum.each(&(PubSub.notify({:prediction, &1, sub_believers})))
    state
  end

  defp make_conjecture_predictions(%Conjecture{predictors: predictors}, state) do
    Enum.map(predictors, &(&1.(state)))
  end


  defp current_round(%State{rounds: [round | _]}) do
    round
  end

  defp sub_generative_model?(name, %State{sub_believers: believer_specs}) do
    Enum.any?(
      believer_specs,
      fn (believer_spec) ->
        case believer_spec do
          {:gm, gm_name} ->
            gm_name == name
          _ -> false
        end
      end
    )
  end

  defp round_timed_out?(%State{gm_def: gm_def} = state) do
    round = current_round(state)
    (now() - round.started_on) >= gm_def.max_round_duration
  end

  defp belief_relevant?(%Belief{source: source}, %State{sub_believers: sub_believers}) do
    source in sub_believers
  end

  # Add a prediction error to the perceptions (a mix of beliefs as predictions by this GM
  # and prediction errors from sub-believers). Remove any created redundancies.
  defp add_prediction_error_to_round(
         %Round{perceptions: perceptions} = round,
         %Belief{} = prediction_error
       ) do
    updated_perceptions = Enum.any?(perceptions, &(Belief.overrides?(&1, prediction_error))) do
      perceptions
    else
      [prediction_error | Enum.reject(perceptions, &(Belief.overrides?(prediction_error, &1)))]
    end
    %Round{round | perceptions: updated_perceptions}
  end

  # All attended-to detectors have provided the current round with a belief
  # All attended-to GMs have provided a belief for each of their active conjectures
  defp round_ready_to_complete?(%State{sub_believers: sub_believers} = state) do
    Enum.all?(
      sub_believers,
      &(not attended_to?(&1, state) or believer_beliefs_received?(&1, state))
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

  # A belief was received from the detector
  defp believer_beliefs_received?({:detector, _} = detector_spec, state) do
    %Round{perceptions: perceptions} = current_round(state)
    Enum.any?(perceptions, &(&1.source == detector_spec))
  end

  # The sub-GM has reported completing a round during the current round of this GM
  defp believer_beliefs_received?({:gm, gm_name} = _gm_spec, state) do
    round = current_round(state)
    gm_name in round.reported_in
  end

  # Complete execution of the current round and set up the next round
  defp complete_round(state) do
    state
    # Carry over missing perceptions (predictions from this GM and prediction errors from sub-believers)
    # from prior round to current round (typically because of timeout)
    |> fill_out_perceptions()
      # Update the attention paid to each sub-believer based on prediction errors
      #  about competing perceptions (their beliefs)
    |> update_attention()
      # Set this GM's belief levels in its perceptions (beliefs of sub-believers), given
      # possible prediction errors (this GM made predictions about the incoming beliefs of sub-believers)
      # and the GM's attention to the perception sources (i.e. the sub-GMs that communicated the perceptions/beliefs)
    |> set_perception_belief_levels()
      # Carry over missing, applicable predictions by super-GMs from prior round to current round
    |> fill_out_received_predictions()
      # Compute beliefs in the GM's own conjectures, assign prediction errors from super-GMs predictions,
      # and communicate prediction errors
    |> compute_beliefs_and_prediction_errors()
      # Re-assess efficacies of courses of action taken in previous rounds given current beliefs
      # Have the CoAs caused the desired belief validations?
    |> update_efficacies()
      # Determine courses of action to achieve each non-yet-achieved goal, or to better validate a non-goal conjecture
    |> set_courses_of_action()
      # Make and communicate predictions about what beliefs are expected next from sub-believers
    |> make_predictions()
      # Execute the currently set courses of action
    |> execute_courses_of_action()
      # Terminate the current round (set completed_on, communicate round_completed)
    |> mark_round_completed()
      # Drop obsolete rounds (forget the distant past)
    |> drop_obsolete_rounds()
      # Add the next round
    |> add_new_round()
      # Set active conjectures, some possibly goals, in the next round
    |> activate_conjectures()
      # Trigger the detectors needed to verify the GM's current active conjectures
    |> trigger_detection()
  end

  defp fill_out_perceptions(%State{rounds: [_round]} = state) do
    state
  end

  # If no current perception from a sub_believer, copy previous perceptions from it except
  # for those that conflict with a predicted perception.
  defp fill_out_perceptions(
         %State{
           sub_believers: sub_believers,
           rounds: [
             %Round{perceptions: perceptions} = round,
             %Round{perceptions: previous_perceptions} = previous_round | other_rounds
           ]
         } = state
       ) do
    filled_out_perceptions = Enum.reduce(
      sub_believers,
      perceptions,
      fn (sub_believer, acc) ->
        if Enum.any?(perceptions, &(&1.source == sub_believer)) do
          acc
        else
          fillers = Enum.filter(previous_perceptions, &(&1.source == sub_believer))
                    |> Enum.reject(
                         fn (%Belief{name: name, about: about} = _previous_perception) ->
                           Enum.any?(perceptions, &(&1.name == name and &1.about == about and &1.source == :prediction))
                         end
                       )
          fillers ++ acc
        end
      end
    )
    %State{
      state |
      rounds: [%Round{round | perceptions: filled_out_perceptions}, previous_round | other_rounds]
    }
  end

  # Grab from previous round any missing predictions about beliefs from active conjectures
  defp fill_out_received_predictions(%State{rounds: [_round]} = state) do
    state
  end

  defp fill_out_predictions(
         %State{
           rounds: [
             %Round{received_predictions: predictions} = round,
             %Round{received_predictions: previous_predictions} = previous_round | other_rounds
           ]
         } = state
       ) do
    filled_out_predictions = Enum.reduce(
      conjecture_activations(state),
      predictions,
      fn (conjecture_activation, acc) ->
        if Enum.any?(acc, &(&1.name == conjecture_activation.conjecture_name)) do
          acc
        else
          Enum.filter(previous_predictions, &(&1.name == conjecture_activation.conjecture_name)) ++ acc
        end
      end
    )
    %State{
      state |
      rounds: [%Round{round | received_predictions: filled_out_predictions}, previous_round | other_rounds]
    }
  end

  # Compute beliefs (with levels thereof) in active conjectures given current state of the GM
  # Also computes the prediction errors given the predictions made by super-GMs
  defp compute_beliefs_and_prediction_errors(
         %State{rounds: [%Round{received_predictions: predictions} = round | previous_rounds]} = state
       ) do
    beliefs = conjecture_activations(state)
              |> Enum.map(&(create_belief(&1, state)))
              |> Enum.map(&(compute_prediction_error(&1, predictions)))
    Enum.each(
      beliefs,
      fn (belief) ->
        if belief.prediction_error > 0.0 do
          PubSub.notify({:prediction_error, belief})
        end

      end
    )
    %State{state | rounds: [%Round{round | beliefs: beliefs} | previous_rounds]}
  end

  defp activated_conjectures(state) do
    conjecture_activations(state)
    |> Enum.map(&(activated_conjecture(&1, state)))
  end

  # Get the current conjecture activations
  defp conjecture_activations(state) do
    %Round{conjecture_activations: conjecture_activations} = current_round(state)
    conjecture_activations
  end

  # Get the conjecture for a conjecture activation
  defp activated_conjecture(%ConjectureActivation{conjecture_name: conjecture_name}, %State{gm_def: gm_def}) do
    Enum.find(gm_def.conjectures, &(&1.name == conjecture_name))
  end

  # Take the average prediction error
  defp compute_prediction_error(
         %Belief{name: name, about: about, parameter_values: parameter_values} = belief,
         predictions
       ) do
    errors = Enum.filter(predictions, &(&1.about == about and &1.name == name))
             |> Enum.map(&(do_compute_prediction_error(parameter_values, &1.parameter_sub_domains)))
    prediction_error = case errors do
      [] ->
        # no predictions so no error (or error = 0.0)
        0.0
      _ ->
        Enum.reduce(errors, 0.0, &(&1 + &2)) / Enum.count(errors)
    end
    %Belief{belief | prediction_error: prediction_error}
  end

  defp do_compute_prediction_error(parameter_values, parameter_sub_domains) do
    value_errors = Enum.reduce(
      parameter_values,
      [],
      fn ({param_name, param_value}, acc) ->
        param_sub_domain = Map.get(parameter_sub_domains, param_name)
        value_error = compute_value_error(param_value, param_sub_domain)
        [value_error | acc]
      end
    )
    # Retain the maximum value error
    Enum.reduce(value_errors, 0, &(max(&1, &2)))
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
      true -> 1.0
    end
  end

  defp compute_value_error(value, list) when is_list(list) do
    if value in list do
      0
    else
      1
    end
  end

  # Give more/less attention to sub-GMs given how well competing beliefs (in this GM's perceptions) matched this GM's predictions.
  # Temper by previous attention level.
  defp update_attention(%State{rounds: [round | other_rounds]} = state) do
    attention = previous_attention(state)
    %Round{perceptions: perceptions} = current_round(state)
    sub_conjectures_believed = Enum.map(perceptions, &(&1.about))
                               |> Enum.uniq()
    attention_levels_per_perception_sources = Enum.reduce(
      sub_conjectures_believed,
      %{},
      fn (sub_conjecture_name, acc) ->
        # Find competing perceptions for the same conjecture
        competing_perceptions_for_conjecture = Enum.filter(
          perceptions,
          &(&1.about == sub_conjecture_name)
        )
        # Spread 1.0 worth of attention among competing sources for that conjecture
        attention_spreads = spread_attention(competing_perceptions_for_conjecture, attention)
        # Aggregate new attention levels across perceptions per source (sub-believer)
        Enum.reduce(
          attention_spreads,
          acc,
          fn ({believer_spec, attention_level}, acc1) ->
            Map.put(acc1, believer_spec, [attention_level | Map.get(acc1, believer_spec, [])])
          end
        )
      end
    )
    updated_attention = Enum.reduce(
      attention_levels_per_perception_sources,
      attention,
      fn ({believer_spec, levels}, acc) ->
        average = Enum.sum(levels) / Enum.count(levels)
        Map.put(acc, believer_spec, average)
      end
    )
    updated_round = %Round{attention: updated_attention}
    %State{state | rounds: [updated_round | previous_rounds]}
  end

  defp previous_attention(%State{rounds: [round]}) do
    %{}
  end

  defp previous_attention(%State{rounds: [_round, %Round{attention: attention} = _previous_round | _]}) do
    attention
  end

  defp spread_attention([%Belief{source: believer_spec} = _perception], _attention) do
    {believer_spec, 1.0}
  end

  # Spread 1.0 worth of attention among competing sources for beliefs, based on prediction errors and prior attention
  defp spread_attention(competing_beliefs, prior_attention) do
    source_raw_levels = Enum.zip(
      Enum.map(competing_beliefs, &(&1.source)),
      Enum.map(
        competing_beliefs,
        &((1.0 - &1.prediction_error) + (Map.get(prior_attention, &1.source, 1.0) / 2.0))
      )
    )
    levels_sum = Enum.sum(source_raw_levels)
    Enum.map(
      source_raw_levels,
      fn ({believer_spec, raw_level}) ->
        {believer_spec, raw_level / levels_sum}
      end
    )
  end

  # Set the perception belief levels for the new perception based on prediction error and attention paid to their sources
  defp set_perception_belief_levels(
         %State{
           rounds: [%Round{perceptions: beliefs, attention: attention} = round | previous_rounds]
         } = state
       ) do
    updated_beliefs = Enum.map(
      beliefs,
      fn (%Belief{source: believer_spec, prediction_error: prediction_error} = belief) ->
        attention_level = Map.get(attention, believer_spec, 1.0)
        %Belief{belief | level: attention_level * (1.0 - prediction_error)}
      end
    )
    %State{state | rounds: [%Round{round | perceptions: updated_beliefs} | previous_rounds]}
  end

  # A CoA's efficacy goes up when correlated to realized beliefs (levels > 0.5) from the same conjecture that prompted it.
  # The closer the validated belief follows the execution of a CoA meant to validate it, the higher the correlation
  defp update_efficacies(
         %State{
           efficacies: efficacies, # %{conjecture_name: [efficacy, ...]}
           rounds: [round | _previous_rounds] = rounds
         } = state
       ) do
    updated_efficacies = Enum.reduce(
      round.beliefs,
      efficacies,
      &(update_efficacies_from_belief(&1, efficacies, rounds))
    )
    %State{state | efficacies: updated_efficacies}
  end

  # Update efficacies given a new belief
  defp update_efficacies_from_belief(
         %Belief{
           name: name, # conjecture name
           level: level
         },
         efficacies,
         rounds
       ) do
    updated_conjecture_efficacies = Map.get(efficacies, name)
                                    |> revise_conjecture_efficacies(level, rounds)
    Map.put(efficacies, about, updated_conjecture_efficacies)
  end

  # Revise the efficacies of CoAs executed in all rounds and prompted by a conjecture about the new belief, given its level.
  defp revise_conjecture_efficacies(conjecture_efficacies, new_belief_level, rounds) do
    Enum.reduce(
      conjecture_efficacies,
      [],
      fn (%Efficacy{course_of_action: course_of_action, degree: degree} = efficacy, acc) ->
        updated_degree = update_efficacy_degree(course_of_action, new_belief_level, degree, rounds)
        [%Efficacy{efficacy | degree: updated_degree} | acc]
      end
    )
  end

  # Update the degree of efficacy of a CoA in achieving the current belief level
  # across all (remembered) rounds where it was executed
  defp update_efficacy_degree(course_of_action, belief_level, degree, rounds) do
    number_of_rounds = Enum.count(rounds)
    indices_of_rounds_with_coa = Enum.reduce(
                                   0..(number_of_rounds - 1),
                                   [],
                                   fn (index, acc) ->
                                     %Round{courses_of_action: courses_of_action} = Enum.at(rounds, index)
                                     if course_of_action in courses_of_action, do: [index | acc], else: acc
                                   end
                                 )
                                 |> Enum.reverse()
    number_of_rounds_with_coa = Enum.count(indices_of_rounds_with_coa)
    impacts_on_belief = Enum.reduce(
                          indices_of_rounds_with_coa,
                          [],
                          fn (round_index, acc) ->
                            closeness = number_of_rounds - round_index
                            round_factor = closeness / number_of_rounds_with_coa # e.g. 4/3, 1/3
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
    {courses_of_action, updated_indices} = Enum.map(activated_conjectures(state), &(select_course_of_action(&1, state)))
                                           |> Enum.reduce(
                                                {%{}, courses_of_action_indices},
                                                fn ({conjecture_name, course_of_action, updated_coa_index},
                                                   {coas, indices} = _acc) ->
                                                  {
                                                    Map.put(coas, conjecture_name, course_of_action),
                                                    Map.put(indices, conjecture_name, updated_coa_index)
                                                  }
                                                end
                                              )
    # one course of action per active conjecture name
    updated_round = %Round{round | courses_of_action: courses_of_action}
    %State{
      state |
      courses_of_action_indices: Map.merge(courses_of_action_indices, updated_indices),
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
    untried_coa = new_course_of_action(
      conjecture,
      coa_index
    )
    # Collect all tried CoAs for the conjecture as candidates as [{CoA, efficacy}, ...]
    tried = Map.get(efficacies, conjecture.name)
            |> Enum.map(&({&1.course_of_action, &1.degree}))
    average_efficacy = average_efficacy(tried)
    candidates = [{untried_coa, average_efficacy} | tried]
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
    (
      Enum.map(tried, &(elem(&1, 1)))
      |> Enum.sum()) / Enum.count(tried)
  end

  defp new_course_of_action(%Conjecture{intention_domain: intention_domain}, courses_of_action_index) do
    # Convert the index into a list of indices e.g. 4 -> [1,1] , 5th CoA (0-based index) in an intention domain of 3 actions
    index_list = Integer.to_string(courses_of_action_index, Enum.count(intention_domain))
                 |> String.to_charlist()
                 |> Enum.map(&(List.to_string([&1])))
                 |> Enum.map(&(String.to_integer(&1)))
    Enum.reduce(
      index_list,
      [],
      fn (i, acc) ->
        [Enum.at(intention_domain, i) | acc]
      end
    )
    |> Enum.reverse()
  end

  # Return [{coa, efficacy}, ...] such that the sum of all efficacies == 1.0
  defp normalize_efficacies(candidate_courses_of_action) do
    sum = Enum.reduce(
      candidate_courses_of_action,
      0,
      fn ({_cao, efficacy}, acc) ->
        efficacy + acc
      end
    )
    Enum.reduce(
      candidate_courses_of_action,
      [],
      fn ({cao, efficacy}, acc) ->
        [{cao, efficacy / sum}, acc]
      end
    )
  end

  defp normalize_values(values) do
    sum = Enum.sum(values)
    Enum.reduce(values, 0, &((&1 / sum) + &2))
    |> Enum.reverse()
  end

  # Randomly pick a course of action with a probability proportional to its efficacy
  defp pick_course_of_action([{coa, _efficacy}]) do
    coa
  end

  defp pick_course_of_action(candidate_courses_of_action) do
    {ranges_reversed, _} = Enum.reduce(
      candidate_courses_of_action,
      {[], 0},
      fn ({_coa, efficacy}, {ranges_acc, top_acc}) ->
        {[top_acc + efficacy | ranges_acc], top_acc + efficacy}
      end
    )
    ranges = Enum.reverse(ranges_reversed)
    Logger.info("Ranges = #{inspect ranges} for courses of action #{candidate_courses_of_action}")
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
      fn ({_conjecture_name, intentions}, executed) ->
        new_intentions = Enum.reject(intentions, &(&1.intent_name in executed))
        Enum.each(
          new_intentions,
          &(PubSub.notify_intended(
              Intent.new(
                about: &1.intent_name,
                value: &1.valuator.(state)
              )
            ))
        )
        Enum.map(new_intentions, &(&1.intent_name)) ++ executed
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
    cutoff = now() - (@forget_round_after_secs * 1000)
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
    goals = Enum.filter(gm_def.conjectures, &(&1.motivator.(state)))
            |> Enum.map(&(&1.name))
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