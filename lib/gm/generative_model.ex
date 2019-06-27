defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger
  import Andy.Utils, only: [listen_to_events: 2, now: 0]
  alias Andy.GM.{PubSub, GenerativeModelDef, Belief}
  @behaviour Andy.GM.Believer

  @forget_after 10_000 # for how long perception is retained

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
                # names of sub-gm that reported a completed round
              predictions: [],
                # [prediction, ...] predictions about the parameter values of beliefs expected from sub-believers in this round
              perceptions: %{},
                # sub_believer => [belief, ...] beliefs received from sub-believers
              beliefs: %{},
                # beliefs in GM conjectures given prediction successes and errors - conjecture_name => Belief
              courses_of_action: %{} # conjecture_name => [action, ...] - courses of action taken
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
          rounds: [initial_round(generative_model_def)]
        }
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
      updated_round = [name | reported_in]
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

  def handle_event(_event, state) do
    state
  end

  ### Believer

  def something_or_other() do
    # TODO
    []
  end

  ### PRIVATE

  defp initial_round(gm_def) do
    %Round{
      beliefs: GenerativeModelDef.initial_beliefs(gm_def),
      started_on: now()
    }
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
  end

  defp execute_round(%State{definition: generative_model_def, rounds: [round | previous_rounds]} = state) do
    # TODO
    round_ts = now()

    # Make predictions for each conjecture for the next round
    # Compute beliefs, using prior beliefs as defaults - add beliefs to current round. Raise "predicted" or "new belief" events.
    # Drop obsolete rounds
    # Re-assess efficacies of courses of action
    # also: update the attention paid to each sub-believer (based on prediction errors?)
    #       update which conjectures are current goals
    # Determine, record and execute a course of actions for each non-achieved goal, or to better validate a non-goal conjecture
    # Set the round ts
    PubSub.notify_after(
      {:round_timed_out, name},
      generative_model_def.max_round_duration
    )
    %State{state | round_ts: round_ts}
  end

end