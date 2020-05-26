defmodule Andy.GM.Round do
  @moduledoc "A round for a generative model. Also serves as episodic memory."

  alias __MODULE__
  alias Andy.GM.{GenerativeModelDef, State}
  alias Andy.Intent
  import Andy.Utils, only: [now: 0]
  import Andy.GM.Utils, only: [info: 1]

  require Logger

  # for how long rounds are remembered (long-term memory)
  @forget_round_after_secs 60

  defstruct id: nil,
            # = the Nth round
            index: nil,
            started_on: nil,
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
            intents: [],
            # whether round is on an early timeout (otherwise would have completed too soon
            early_timeout_on: false,
            # A snaphot of efficacies at the time the round completed
            efficacies_snapshot: []

  def new(gm_def, index) do
    initial_beliefs = GenerativeModelDef.initial_beliefs(gm_def)

    Logger.info(
      "#{inspect(gm_def.name)}(#{index}): Initial beliefs are #{inspect(initial_beliefs)}"
    )

    %Round{
      id: UUID.uuid4(),
      index: index,
      beliefs: initial_beliefs,
      started_on: now()
    }
  end

  def round_status(state, status) do
    %State{state | round_status: status}
  end

  def next_round_index([round | _]) do
    round.index + 1
  end

  def has_intents?(%Round{intents: intents}) do
    Enum.count(intents) > 0
  end

  def intents_duration(%Round{intents: intents}) do
    Enum.map(intents, &Intent.duration(&1)) |> Enum.sum()
  end

  def intent_names(%Round{intents: intents}) do
    Enum.map(intents, &Intent.name(&1))
  end

  def current_round(%State{rounds: [round | _]}) do
    round
  end

  def round_timed_out?(round_id, %State{} = state) do
    %Round{id: id} = current_round(state)
    round_id == id
  end

  def current_round?(round_id, state) do
    %Round{id: id} = current_round(state)
    id == round_id
  end

  # Close the current round (set completed_on, report round_completed)
  # and get the next round going
  def close_round(%State{} = state) do
    Logger.info("#{info(state)}: Closing round")

    state
    |> mark_round_completed()
    |> remember_efficacies()
    # Drop obsolete rounds (forget the distant past)
    |> drop_obsolete_rounds()
  end

  def rounds_since([], _since) do
    []
  end

  def rounds_since([%Round{completed_on: completed_on} = round | previous_rounds], since) do
    if completed_on > since do
      rounds_since(previous_rounds, since) ++ [round]
    else
      []
    end
  end

  def longest_round_sequence(rounds, test) do
    longest = do_longest_round_sequence(rounds, test, [[]])
    Logger.info("Longest sequence of rounds #{inspect(longest)}")
    longest
  end

  ### PRIVATE

  defp mark_round_completed(%State{rounds: [round | previous_rounds]} = state) do
    %State{state | rounds: [%Round{round | completed_on: now()} | previous_rounds]}
  end

  defp remember_efficacies(
         %State{rounds: [round | previous_rounds], efficacies: efficacies} = state
       ) do
    %State{
      state
      | rounds: [
          %Round{
            round
            | completed_on: now(),
              efficacies_snapshot: List.flatten(Map.values(efficacies))
          }
          | previous_rounds
        ]
    }
  end

  defp drop_obsolete_rounds(%State{rounds: rounds} = state) do
    remembered_rounds = do_drop_obsolete_rounds(rounds)

    Logger.info(
      "#{info(state)}: Dropping #{Enum.count(rounds) - Enum.count(remembered_rounds)} obsolete rounds"
    )

    %State{state | rounds: remembered_rounds}
  end

  defp do_drop_obsolete_rounds([]), do: []

  defp do_drop_obsolete_rounds([round | older_rounds]) do
    cutoff = now() - @forget_round_after_secs * 1000

    if round.completed_on > cutoff do
      [round | do_drop_obsolete_rounds(older_rounds)]
    else
      # every other round is also necessarily obsolete
      []
    end
  end

  defp do_longest_round_sequence([], _test, sequences) do
    case Enum.sort(sequences, &(Enum.count(&1) >= Enum.count(&2))) do
      [] ->
        []

      [longest | _] ->
        longest |> Enum.reverse()
    end
  end

  defp do_longest_round_sequence([round | previous_rounds], test, [sequence | others]) do
    if test.(round) do
      do_longest_round_sequence(previous_rounds, test, [[round | sequence] | others])
    else
      do_longest_round_sequence(previous_rounds, test, [[]] ++ [sequence | others])
    end
  end
end
