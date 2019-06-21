defmodule Andy.GM.GenerativeModel do
  @moduledoc "A generative model agent"

  require Logger
  import Andy.Utils, only: [listen_to_events: 2]
  alias Andy.GM.{Belief}
  @behaviour Andy.GM.Believer

  @forget_after 10_000 # for how long perception is retained

  defmodule State do
    defstruct definition: nil,
                # a GenerativeModelDef - static
              sub_believers: [],
                # Specs of Believers that feed into this GM according to the GM graph
              round_timer: nil,
                # pid of round timer
              rounds: [],
                # latest rounds of activation of the generative model
              attention: %{},
                # attention currently given to sub-believers - believer_name => float
              goals: [],
                # names of conjectures that are currently goals to be achieved
              efficacies: %{
              } # conjecture_name => [efficacy, ...]  the efficacies of tried courses of action to achieve a goal conjecture
  end

  defmodule Round do
    @moduledoc "A round for a generative model"

    defstruct round_timestamp: nil,
                # timestamp for the round
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
          rounds: [initial_round(generative_model_def)],
          round_timer: spawn_link(fn -> complete_round(generative_model_def) end)
        }
      end,
      [name: name]
    )
    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  ### Event handling by the agent

  def handle_event({:believed, belief}, state) do
    if belief_relevant?(belief, state) do
      process_received_belief(belief, state)
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
    # TODO
    %Round{}
  end

  defp belief_relevant?(%Belief{conjecture_name: conjecture_name}, %State{definition: gm_def}) do
    # TODO
    false
  end

  defp process_received_belief(belief, state) do
    # TODO
    # Add to perception
    # If all sub-believers contributed their full range of beliefs, immediately complete the round
    state
  end

  defp complete_round(generative_model_def) do
    :timer.sleep(generative_model_def.max_round_duration)
    Logger.info("Completing round for GM #{generative_model_def.name}")
    :ok = Agent.update(generative_model_def.name, fn (state) -> execute_round(state) end)
    complete_round(generative_model_def)
  end

  defp initial_beliefs(_generative_model_def) do
    # TODO
    %{}
  end

  defp execute_round(state) do
    # TODO
    # Stop the round timer
    # Make predictions for each conjecture
    # Compute beliefs, using prior beliefs as defaults - add beliefs to current round. Raise "predicted" or "new belief" events.
    # Drop obsolete rounds
    # Re-assess efficacies of courses of action
    # also: update the attention paid to each sub-believer (based on prediction errors?)
    #       update which conjectures are current goals
    # Determine, record and execute a course of actions for each non-achieved goal, or to better validate a non-goal conjecture
    # Restart the round timer
    state
  end

end