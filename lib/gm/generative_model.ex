defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.GM.{PubSub, GenerativeModelDef, Belief}
  @behaviour Andy.GM.Believer

  @forget_round_after_secs 60 # for how long rounds are remembered

  defmodule State do
    defstruct gm_def: nil,
                # a GenerativeModelDef - static
                # Specs of Believers that feed into this GM according to the GM graph
              sub_believers: [],
                # latest rounds of activation of the generative model
              rounds: [],
                # attention currently given to sub-believers - believer_spec => float from 0 to 1 (complete attention)
              attention: %{},
                # names of conjectures that are currently goals to be achieved
              goals: [],
                # conjecture_name => [efficacy, ...] - the efficacies of tried courses of action to achieve a goal conjecture
              efficacies: %{},
                # conjecture_name => course of action index
              courses_of_action_indices: %{}
  end

  defmodule Round do
    @moduledoc "A round for a generative model"

    defstruct started_on: nil,
              completed_on: nil,
                # names of sub-gm that reported a completed round
              reported_in: [],
                # names of active conjectures
              active_conjectures: [],
                # [belief, ...] - perceptions are the communicated beliefs of sub-believers
              perceptions: [],
                # [prediction, ...] predictions communicated by super-GMs about this GM's beliefs
              predictions: [],
                # beliefs in this GM conjectures given communicated perceptions
              beliefs: [],
                # conjecture_name => [action_name, ...] - courses of action taken to achieve goals or shore up beliefs
              courses_of_action: %{}

    def new() do
      %Round{stated_on: now()}
    end

    def initial_round(gm_def) do
      %Round{Round.new() | beliefs: GenerativeModelDef.initial_beliefs(gm_def)}
    end

  end

  defmodule Efficacy do
    @moduledoc """
    The historical efficacy of a course of action to validate a conjecture as a goal.
    Efficacy is gauged by the proximity of the CoA to a future round that achieves the goal,
    tempered by any prior efficacy measurement.
    """

    defstruct level: 0,
                # level of efficacy, float from 0 to 1
              course_of_action: [] # [action, ...] a course of action
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
          rounds: [Round.initial_round(gm_def)]
        }
        # Set which conjectures are goals
        |> set_goals()
          # Activate conjectures
        |> activate_conjectures()
      end,
      [name: name]
    )
    listen_to_events(pid, __MODULE__)
    PubSub.notify_after(
      {:round_timed_out, name},
      gm_def.max_round_duration
    )
    {:ok, pid}
  end

  ### Event handling by the agent

  def handle_event(
        {:round_timed_out, name},
        %State{gm_def: gm_def} = state
      ) do
    if name == gm_def.name do
      if round_timed_out?(state) do # could be an obsolete round time out event from a round that completed early
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

  def handle_event(
        {
          :believed,
          belief
        },
        %State{gm_def: gm_def, rounds: [round | previous_rounds]} = state
      ) do
    if belief_relevant?(belief, state) do
      updated_round = add_perception_to_round(round, belief)
      updated_state = %State{state | rounds: [updated_round | previous_rounds]}
      if round_ready_to_complete?(updated_state) do
        completed_state = complete_round(updated_state)
        PubSub.notify_after(
          {:round_timed_out, name},
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

  def handle_event(
        {:prediction, prediction, target_gms},
        %State{gm_def: gm_def, rounds: [round | previous_rounds]} = state
      ) do
    if gm_def.name in target_gms do
      updated_round = %Round{round | predictions: [prediction | round.predictions]}
      %State{state | rounds: [updated_round | previous_rounds]}
    else
      state
    end
  end

  def handle_event(_event, state) do
    state
  end

  ### Believer

  def something_or_other() do
    # TODO
    []
  end

  ### PRIVATE

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
    (now() - round.timestamp) >= gm_def.max_round_duration
  end

  defp belief_relevant?(%Belief{source: source}, %State{sub_believers: sub_believers}) do
    source in sub_believers
  end

  defp add_perception_to_round(
         %Round{perceptions: perceptions} = round,
         %Belief{
         } = belief
       ) do
    %Round{round | perceptions: [belief | perceptions]}
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
  defp attended_to?(believer_spec, %State{attention: attention}) do
    Map.get(attention, believer_spec, 1.0) > 0
  end

  # A belief was received from the detector
  defp believer_beliefs_received?({:detector, _} = detector_spec, state) do
    round = current_round(state)
    count = Map.get(round.perceptions, detector_spec, [])
            |> Enum.count()
    count > 0
  end

  # The sub-GM has reported completing a round during the current round of this GM
  defp believer_beliefs_received?({:gm, gm_name} = gm_spec, state) do
    round = current_round(state)
    gm_name in round.reported_in
  end

  # Complete execution of the current round and set up the next round
  defp complete_round(%State{gm_def: gm_def, rounds: [round | previous_rounds] = rounds} = state) do
    state
    # Carry over missing perceptions from prior round to current round
    |> fill_out_perceptions()
      # Update the attention paid to each sub-believer based on prediction errors on competing perceptions (their beliefs)
    |> update_attention()
      # Set this GM's belief levels in the perceptions, given prediction errors and GM's attention to sources (the sub-GMs that communicated the perceptions/beliefs)
    |> set_perception_belief_levels()
      # Carry over missing, applicable predictions by super-GMs from prior round to current round
    |> fill_out_predictions()
      # Compute beliefs in the GM's own conjectures, assign prediction errors from super-GMs, and publish to super-GMs to become their perceptions
    |> compute_beliefs()
      # Re-assess efficacies of courses of action taken in previous rounds given current beliefs
    |> update_efficacies()
      # Determine a course of actions for each non-achieved goal, or to better validate a non-goal conjecture
    |> set_courses_of_action()
      # Make predictions about what beliefs are expected next from sub-believers
    |> make_predictions()
      # Execute courses of action
    |> execute_courses_of_action()
      # Terminate current round (set completed_on, publish round_completed)
    |> mark_round_completed()
      # Drop obsolete rounds
    |> drop_obsolete_rounds()
      # Add next round
    |> add_new_round()
      # Set which conjectures are goals in the next round
    |> set_goals()
      # Set active conjectures in the next round
    |> activate_conjectures()
  end

  defp fill_out_perceptions(%State{rounds: [round]} = state) do
    state
  end

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
        case Enum.find(perceptions, &(&1.source == sub_believer)) do
          nil ->
            case Enum.find(previous_perceptions, &(&1.source == sub_believer)) do
              nil ->
                acc
              previous_perception ->
                [previous_perception | acc]
            end
          perception ->
            acc
        end
      end
    )
    %State{
      state |
      rounds: [%Round{round | perceptions: filled_out_perceptions}, previous_round | other_rounds]
    }
  end

  # Grab from previous round any missing prediction about beliefs from active conjectures
  defp fill_out_predictions(%State{rounds: [round]} = state) do
    state
  end

  defp fill_out_predictions(
         %State{
           rounds: [
             %Round{predictions: predictions} = round,
             %Round{predictions: previous_predictions} = previous_round | other_rounds
           ]
         } = state
       ) do
    filled_out_predictions = Enum.reduce(
      active_conjectures(state),
      predictions,
      fn (active_conjecture, acc) ->
        if Enum.any?(acc, &(&1.about == active_conjecture.about)) do
          acc
        else
          case Enum.find(previous_predictions, &(&1.about == active_conjecture.about)) do
            nil ->
              acc
            previous_prediction ->
              [previous_prediction | acc]
          end
        end
      end
    )
    %State{
      state |
      rounds: [%Round{round | predictions: filled_out_predictions}, previous_round | other_rounds]
    }
  end

  defp compute_beliefs(%State{rounds: [%Round{predictions: predictions} = round | previous_rounds]} = state) do
    beliefs = active_conjectures(state)
              |> Enum.map(&(&1.validator.(state)))
              |> Enum.map(&(compute_prediction_error(&1, predictions)))
    %State{state | rounds: [%Round{round | beliefs: beliefs} | previous_rounds]}
  end

  # Take the average prediction error
  defp compute_prediction_error(%Belief{about: about, parameter_values: parameter_values} = belief, predictions) do
    errors = Enum.filter(predictions, &(&1.about == about))
             |> Enum.map(&(do_compute_prediction_error(parameter_values, &1.parameter_sub_domains)))
    prediction_error = case errors do
      [] ->
        0
      _ ->
        Enum.reduce(errors, 0, &(&1 + &2)) / Enum.count(errors)
    end
    %Belief{belief | prediction_error: prediction_error}
  end

  defp do_compute_prediction_error(parameter_values, parameter_sub_domains) do
    value_errors = Enum.reduce(
      Map.keys(parameter_values),
      [],
      fn (param_name, acc) ->
        param_value = Map.get(parameter_values, param_name)
        param_sub_domain = Map.get(parameter_sub_domains, param_name)
        value_error = compute_value_error(param_value, param_sub_domain)
        [value_error | acc]
      end
    )
    # Retain the maximum value error
    Enum.reduce(value_errors, 0, &(max(&1, &2)))
  end

  defp compute_value_error(value, sub_domain) when sub_domain in [nil, []] do
    0
  end

  defp compute_value_error(value, low..high = range) when is_number(value) do
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

  defp compute_value_error(value, list) when is_list(value) do
    if value in list do
      0
    else
      1
    end
  end

  defp make_predictions(%State{gm_def: gm_def, sub_believers: sub_believers} = state) do
    active_conjectures(state)
    |> Enum.map(&(make_conjecture_predictions(&1, state)))
    |> List.flatten()
    |> Enum.each(PubSub.notify({:prediction, &1, sub_believers}))
    state
  end

  defp active_conjectures(%State{gm_def: gm_def}) do
    %Round{active_conjectures: active_conjectures} = current_round(state)
    Enum.filter(gm_def.conjectures, &(&1.name in active_conjectures))
  end

  defp make_conjecture_predictions(%Conjecture{predictors: predictors}, state) do
    Enum.map(predictors, &(&1.(state)))
  end

  # Give more/less attention to sub-GMs given how well competing beliefs (in this GM's perceptions) matched this GM's predictions.
  # Temper by previous attention level.
  defp update_attention(%State{attention: attention} = state) do
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
    %State{state | attention: updated_attention}
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

  # A CoA efficacy goes up when correlated to realized beliefs (levels > 0.5) from the same conjecture
  # The more recent the belief, the higher the correlation
  defp update_efficacies(state) do
    # TODO
    state
  end

  defp set_perception_belief_levels(
         %State{
           attention: attention,
           rounds: [%Round{perceptions: beliefs} = round | previous_rounds]
         } = state
       ) do
    updated_beliefs = Enum.map(
      beliefs,
      fn (%Belief{source: believer_spec, prediction_error: prediction_error} = belief) ->
        attention_level = Map.get(attention, believer_spec, 1.0)
        %Belief{belief | level: attention_level * (1.0 - prediction_error)}
      end
    )
    %State{state | rounds: [%Round{round | perception: updated_beliefs} | previous_rounds]}
  end

  # For each active conjecture, choose a CoA from the conjecture's CoA domain favoring effectiveness
  # and shortness, looking at longer CoAs only if effectiveness of shorter CoAs disappoints.
  defp set_courses_of_action(
         %State{
           rounds: [round | previous_rounds],
           courses_of_action_indices: courses_of_action_indices
         } = state
       ) do
    {courses_of_action, updated_indices} = Enum.map(active_conjectures(state), &(select_course_of_action(&1, state)))
                                           |> Map.reduce(
                                                {%{}, courses_of_action_indices},
                                                fn ({conjecture_name, course_of_action, updated_coa_index},
                                                   {coas,indices} = _acc) ->
                                                  {
                                                    Map.put(coas, conjecture_name, course_of_action),
                                                    Map.put(indices, conjecture_name, updated_coa_index)
                                                  }
                                                end
                                              )
    updated_round = %Round{round | courses_of_action: courses_of_action}
    %State{
      state |
      course_of_action_indices: Map.merge(courses_of_action_indices, updated_indices),
      rounds: [updated_round | previous_rounds]
    }
  end

  # Select a course of action for a conjecture
  defp select_course_of_action(
         conjecture_name,
         %State{
           gm_def: gm_def,
           efficacies: efficacies,
           courses_of_action_indices: courses_of_action_indices
         } = state
       ) do
    conjecture = GenerativeModelDef.conjecture(gm_def, conjecture_name)
    # Collect all tried CoAs for the conjecture as candidates as [{CoA, efficacy}, ...]
    tried = Map.to_list(efficacies)
    # Create an untried CoA (shortest possible), give it a hypothetical efficacy (= average efficacy) and add it to the candidates
    coa_index = Map.get(courses_of_action_indices, conjecture.name, 0)
    untried_coa = new_course_of_action(
      conjecture,
      coa_index
    )
    average_efficacy = average_efficacy(tried)
    candidates = [{untried_coa, average_efficacy} | tried]
                 # Normalize efficacies (sum = 1.0)
                 |> normalize_efficacies()
    # Pick a CoA randomly, favoring higher efficacy
    course_of_action = pick_course_of_action(candidates)
    # Move the CoA index if we picked an untried CoA
    updated_coa_index = if course_of_action == untried_coa, do: coa_index, else: coa_index + 1
    {conjecture_name, course_of_action, updated_coa_index}
  end

  defp average_efficacy([]) do
    1.0
  end

  defp average_efficacy(tried) do
    (
      Enum.map(tried, &(elem(&1, 1)))
      |> Enum.sum()) / Enum.count(tried)
  end

  defp new_course_of_action(%Conjecture{action_domain: action_domain}, courses_of_action_index) do
    # Convert the index into a list of indices e.g. 4 -> [1,1] , 5th CoA (0-based index) in an action domain of 3 actions
    index_list = Integer.to_string(courses_of_action_index, Enum.count(action_domain))
                 |> String.to_charlist()
                 |> Enum.map(&(List.to_string([&1])))
                 |> Enum.map(&(String.to_integer(&1)))
    Enum.reduce(
      index_list,
      [],
      fn (i, acc) ->
        [Enum.at(action_domain, i) | acc]
      end
    )
    |> List.reverse()
  end

  defp normalize_efficacies(candidate_courses_of_action) do
    # TODO
  end

  defp pick_course_of_action(candidate_courses_of_action) do
    # TODO
  end

  defp execute_courses_of_action(state) do
    # TODO
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

  defp set_goals(%State{gm_def: gm_def, rounds: [round | previous_rounds]} = state) do
    goals = Enum.filter(gm_def.conjectures, &(&1.motivator.(state)))
            |> Enum.map(&(&1.name))
    %State{state | rounds: [%Round{round | goals: goals} | previous_rounds]}
  end

  # Pick as many GM conjectures as possible that do not mutually exclude one another.
  # When choosing which to exclude drop any active one that is not believed
  defp activate_conjectures(
         %State{
           gm_def: gm_def,
           rounds: [round | previous_rounds]
         } = state
       ) do
    # Get previously active conjectures
    previous_active_conjectures = case previous_rounds do
      [] ->
        []
      [previous_round | _] ->
        previous_round.active_conjectures
    end
    # Keep previously believed conjectures
    believed_conjecture_names = Enum.reject(previous_active_conjectures, &(not conjecture_was_believed?(&1, state)))
    # Add conjectures not mentioned and not mutually excluded (use randomness)
    candidates = Enum.map(gm_def.conjectures, &(&1.name))
                 |> Enum.reject(&(&1 in believed_conjecture_names))
                 |> random_permutation()
                 |> remove_excluded(believed_conjecture_names, gm_def.contradictions)
    state
  end

  # Conjecture is believed by default in the initial round
  defp conjecture_was_believed?(_conjecture_name, %State{rounds: [_round]}) do
    true
  end

  # Is conjecture believed in the previous round?
  defp conjecture_was_believed?(conjecture_name, %State{rounds: [_round, previous_round | _]}) do
    Enum.any?(previous_round.beliefs, &(&1.about == conjecture_name and &1.level >= 0.5))
  end

  defp remove_excluded([], _believed_conjecture_names, _contradictions) do
    []
  end

  defp remove_excluded([candidate | other_candidates], believed_conjecture_names, contradictions) do
    if mutually_excluded?(candidate, other_candidates ++ believed_conjecture_names, contradictions) do
      remove_excluded(other_candidates, believed_conjecture_names, contradictions)
    else
      [candidate | remove_excluded(other_candidates, believed_conjecture_names, contradictions)]
    end
  end

  defp mutually_excluded?(candidate, conjecture_names, contradictions) do
    Enum.any?(conjecture_names, &(&1 in contradictions and candidate in contradictions))
  end

  defp random_permutation([]) do
    []
  end

  defp random_permutation(list) do
    chosen = Enum.random(list)
    [chosen | random_permutation(List.delete(list, chosen))]
  end

end