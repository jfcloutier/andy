defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.GM.{PubSub, GenerativeModelDef, Belief}
  @behaviour Andy.GM.Believer

  @forget_round_after_secs 60 # for how long rounds are remembered

  defmodule State do
    defstruct definition: nil,
                # a GenerativeModelDef - static
              sub_believers: [],
                # Specs of Believers that feed into this GM according to the GM graph
              rounds: [],
                # latest rounds of activation of the generative model
              attention: %{},
                # attention currently given to sub-believers - believer_spec => float
              goals: [],
                # names of conjectures that are currently goals to be achieved
              efficacies: %{
              } # conjecture_name => [efficacy, ...]  the efficacies of tried courses of action to achieve a goal conjecture
  end

  defmodule Round do
    @moduledoc "A round for a generative model"

    defstruct started_on: nil,
                # timestamp for the start of round
              completed_on: nil,
                # timestamp of round completion
              reported_in: [],
                # names of active conjectures
              active_conjectures: [],
                # names of sub-gm that reported a completed round
              predictions: [],
                # [prediction, ...] predictions about the parameter values of beliefs expected from sub-believers in this round
              perceptions: %{},
                # sub_believer => [belief, ...] beliefs received from sub-believers
              beliefs: %{},
                # beliefs in GM conjectures given prediction successes and errors - conjecture_name => Belief
              courses_of_action: %{} # conjecture_name => [action, ...] - courses of action taken

    def new() do
      %Round{stated_on: now()}
    end

    def initial_round(gm_def) do
      %Round{
        beliefs: GenerativeModelDef.initial_beliefs(gm_def),
        started_on: now()
      }
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
  def child_spec(generative_model_def, sub_believers) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [generative_model_def, sub_believers]}
    }
  end

  @doc "Start the memory server"
  def start_link(generative_model_def, sub_believer_specs) do
    name = generative_model_def.name
    Logger.info("Starting Generative Model #{name}")
    {:ok, pid} = Agent.start_link(
      fn () ->
        %State{
          definition: generative_model_def,
          sub_believers: sub_believer_specs,
          rounds: [Round.initial_round(generative_model_def)]
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
      generative_model_def.max_round_duration
    )
    {:ok, pid}
  end

  ### Event handling by the agent

  def handle_event(
        {:round_timed_out, name},
        %State{definition: generative_model_def} = state
      ) do
    if name == generative_model_def.name do
      if round_timed_out?(state) do # could be a round time out event from a round that completed early
        new_state = execute_round(state)
        PubSub.notify_after(
          {:round_timed_out, name},
          generative_model_def.max_round_duration
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
      updated_reported_in = [name | reported_in]
      updated_round = %Round{round | reported_in: updated_reported_in}
      %State{rounds: [updated_round | previous_rounds]}
    else
      state
    end
  end

  def handle_event(
        {
          :believed,
          belief
        },
        %State{rounds: [round | previous_rounds]} = state
      ) do
    if belief_relevant?(belief, state) do
      updated_round = add_perception_to_round(round, belief)
      updated_state = %State{state | rounds: [updated_round | previous_rounds]}
      if round_completed?(updated_state) do
        execute_round(updated_state)
      else
        updated_state
      end
    else
      state
    end
  end

  def handle_event(
        {:prediction, prediction, target_gms},
        %State{definition: gm_def, rounds: [round | previous_rounds]} = state
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

  defp round_timed_out?(%State{definition: generative_model_def} = state) do
    round = current_round(state)
    (now() - round.timestamp) >= generative_model_def.max_round_duration
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
  defp round_completed?(%State{sub_believers: sub_believers} = state) do
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

  defp complete_round(generative_model_def) do
    Logger.info("Completing round for GM #{generative_model_def.name}")
    :ok = Agent.update(generative_model_def.name, fn (state) -> execute_round(state) end)
    PubSub.notify_after(
      {:round_timed_out, generative_model_def.name},
      generative_model_def.max_round_duration
    )
  end

  defp execute_round(%State{definition: generative_model_def, rounds: [round | previous_rounds] = rounds} = state) do
    state
    # Carry over missing perceptions from prior round to current round
    |> fill_out_perceptions()
      # Compute beliefs of current round and publish them for super-gms
    |> compute_beliefs()
      # Compute the prediction errors for the new beliefs
    |> compute_prediction_errors()
      # Make predictions from each conjecture for the sub-believers (about what beliefs are expected from them in their current rounds)
    |> make_predictions()
      # Re-assess efficacies of courses of action
    |> update_efficacies()
      # Update the attention paid to each sub-believer (based on prediction errors?)
    |> update_attention()
      # Determine, record and execute a course of actions for each non-achieved goal, or to better validate a non-goal conjecture
    |> set_courses_of_action()
      # Terminate current round (set completed_on, publish round_completed)
    |> mark_round_completed()
      # Drop obsolete rounds
    |> drop_obsolete_rounds()
      # Add new round
    |> add_new_round()
      # Set which conjectures are goals
    |> set_goals()
      # Set active conjectures
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
             %Round{perceptions: previous_perceptions} | previous_rounds
           ]
         } = state
       ) do
    filled_out_perceptions = Enum.reduce(
      sub_believers,
      perceptions,
      fn (sub_believer, acc) ->
        if Map.get(perceptions, sub_believer) == nil do
          Map.put(acc, sub_believer, Map.get(previous_perceptions, sub_believer, []))
        else
          acc
        end
      end
    )
    %State{
      state |
      rounds: [
        %Round{round | perceptions: filled_out_perceptions},
        %Round{perceptions: previous_perceptions} | previous_rounds
      ]
    }
  end

  defp compute_beliefs(state) do
    beliefs = active_conjectures(state)
              |> Enum.map(&(&1.validator.(state)))
    %State{state | beliefs: beliefs}
  end

  defp compute_prediction_errors(
         %State{rounds: [%Round{predictions: predictions, perceptions: perceptions} | previous_rounds]} = state
       ) do
    updated_perceptions = Enum.map(perceptions, &(compute_prediction_error(&1, predictions)))
    updated_round = %Round{round | perceptions: updated_perceptions}
    %State{state | rounds: [updated_round | previous_rounds]}
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

  defp make_predictions(%State{definition: gm_def, sub_believers: sub_believers} = state) do
    active_conjectures(state)
    |> Enum.map(&(make_conjecture_predictions(&1, state)))
    |> List.flatten()
    |> Enum.each(PubSub.notify({:prediction, &1, sub_believers}))
    state
  end

  defp active_conjectures(%State{definition: gm_def}) do
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

  defp set_courses_of_action(state) do
    # TODO
    state
  end

  defp mark_round_completed(%State{definition: gm_def, rounds: [round | previous_rounds]} = state) do
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

  defp activate_conjectures(state) do
    # TODO
    state
  end

  defp set_goals(state) do
    # TODO
    state
  end
end