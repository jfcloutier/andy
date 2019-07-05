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
                # attention currently given to sub-believers - believer_spec => float
              attention: %{},
                # names of conjectures that are currently goals to be achieved
              goals: [],
                # conjecture_name => [efficacy, ...] - the efficacies of tried courses of action to achieve a goal conjecture
              efficacies: %{}
  end

  defmodule Round do
    @moduledoc "A round for a generative model"

    defstruct started_on: nil,
              completed_on: nil,
                # names of sub-gm that reported a completed round
              reported_in: [],
                # names of active conjectures
              active_conjectures: [],
                # sub_believer_spec => [belief, ...] - beliefs received from sub-believers
              perceptions: %{},
                # [prediction, ...] predictions about the (parameter values of) beliefs expected by super-gms in this round
              predictions: [],
                # beliefs in this GM conjectures given prediction successes and errors - conjecture_name => Belief
              beliefs: %{},
                # conjecture_name => [action, ...] - courses of action taken
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
           source: source,
           about: about
         } = belief
       ) do
    source_perceptions = Map.get(perceptions, source, [])
    updated_perceptions = Map.put(
      perceptions,
      source,
      [belief | Enum.reject(source_perceptions, &(&1.about == about))]
    )
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
      # Carry over missing, meaningful predictions by super-GMs from prior round to current round
    |> fill_out_predictions()
      # Set this GM's belief levels in the perceptions from sub-GM(s), given prediction errors and GM's attention to sources
    |> set_perception_belief_levels()
      # Compute beliefs in the GM's own conjectures, with prediction errors, and publish them for super-gms to accumulate them as perceptions
    |> compute_beliefs()
      # Make predictions about what beliefs are expected next from sub-believers
    |> make_predictions()
      # Update the attention paid to each sub-believer (based on prediction errors on perceptions from them etc.)
    |> update_attention()
      # Re-assess efficacies of courses of action taken in this and previous rounds given current beliefs
    |> update_efficacies()
      # Determine, record and execute a course of actions for each non-achieved goal, or to better validate a non-goal conjecture
    |> set_courses_of_action()
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
        if Map.get(acc, sub_believer) == nil do
          Map.put(acc, sub_believer, Map.get(previous_perceptions, sub_believer, []))
        else
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

  defp update_efficacies(state) do
    # TODO
    state
  end

  defp update_attention(state) do
    # TODO
    state
  end

  defp set_perception_belief_levels(state) do
    # TODO
    state
  end

  defp set_courses_of_action(state) do
    # TODO
    state
  end

  defp mark_round_completed(%State{gm_def: gm_def, rounds: [round | previous_rounds]} = state) do
    PubSub.notify({:round_completed, gm_def.name})
    %State{state | rounds: [%Round{round | completed_on: now()} | previous_rounds]}
  end

  defp drop_obsolete_rounds(%State{rounds: rounds} = state) do
    updated_rounds = do_drop_obsolete_rounds(rounds)
    %State{state | rounds: updated_rounds}
  end

  defp do_drop_obsolete_rounds([round | older_rounds] = rounds) do
    cutoff = now() - (@forget_round_after_secs * 1000)
    if round.completed_on > cutoff do
      [rounds | drop_obsolete_rounds(older_rounds)]
    else
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
    believed_conjecture_names = Enum.reject(previous_active_conjectures, &(not conjecture_believed?(&1, state)))
    # Add conjectures not mentioned and not mutually excluded (use randomness)
    candidates = Enum.map(gm_def.conjectures, &(&1.name))
                 |> Enum.reject(&(&1 in believed_conjecture_names))
                 |> random_permutation()
                 |> remove_excluded(believed_conjecture_names, gm_def.contradictions)
    state
  end

  # Conjecture is believed by default in the initial round
  defp conjecture_believed?(_conjecture_name, %State{rounds: [_round]}) do
    true
  end

  # Is conjecture believed in the previous round?
  defp conjecture_believed?(conjecture_name, %State{rounds: [_round, previous_round | _]}) do
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