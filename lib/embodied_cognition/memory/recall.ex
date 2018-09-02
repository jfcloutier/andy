defmodule Andy.Recall do
  @moduledoc "Functions for querying Memory"

  alias Andy.Memory
  require Logger

  # Calculate the probability that the values of a kind of percepts within a given time period add up to a target value
  def probability_of_perceived({ percept_about, { :sum, target_sum }, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    actual_sum = Enum.reduce(
      percepts,
      0,
      fn (%{ value: value } = _percept, acc) ->
        value + acc
      end
    )
    if target_sum == 0, do: 1.0, else: min(1.0, actual_sum / target_sum)
  end

  # Calculate the probability that the values of a kind of percepts within a given time period add up to a target value
  def probability_of_perceived({ percept_about, { :sum, attribute, target_sum }, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    actual_sum = Enum.reduce(
      percepts,
      0,
      fn (%{ value: value } = _percept, acc) ->
        Map.get(value, attribute) + acc
      end
    )
    if target_sum == 0, do: 1.0, else: min(1.0, actual_sum / target_sum)
  end

  # Calculate the probability that percepts a kind of percepts within a given time period validate a predicate
  def probability_of_perceived({ percept_about, predicate, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    percepts_count = Enum.count(percepts)
    Logger.info("Recalled #{percepts_count} percepts matching #{inspect percept_about} over #{inspect time_period}: #{inspect percepts}")
    fitting_percepts = Enum.filter(percepts, &(apply_predicate(predicate, &1, percepts)))
    fitting_count = Enum.count(fitting_percepts)
    Logger.info("Fitting #{fitting_count} percepts with predicate #{inspect predicate}")
    if percepts_count == 0, do: 0, else: fitting_count / percepts_count
  end

  # Calculate the probability that the values of a kind of actuated intents within a given time period add up to a target value
  def probability_of_actuated({ intent_about, { :sum, target_sum }, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    actual_sum = Enum.reduce(
      intents,
      0,
      fn (%{ value: value } = _intent, acc) ->
        value + acc
      end
    )
    Logger.info(
      "Sum of of intents #{inspect intent_about} is #{actual_sum} out of target #{target_sum} in #{
        inspect time_period
      }"
    )
    if target_sum == 0, do: 1.0, else: min(1.0, actual_sum / target_sum)
  end

  # Calculate the probability that the values of a kind of actuated intents within a given time period add up to a target value
  def probability_of_actuated({ intent_about, { :sum, attribute, target_sum }, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    actual_sum = Enum.reduce(
      intents,
      0,
      fn (%{ value: value } = _intent, acc) ->
        Map.get(value, attribute) + acc
      end
    )
    Logger.info(
      "Sum of #{attribute} of intents #{inspect intent_about} is #{actual_sum} out of target #{target_sum} in #{
        inspect time_period
      }"
    )
    if target_sum == 0, do: 1.0, else: min(1.0, actual_sum / target_sum)
  end

  # Calculate the probability that actuated intents of a certain kind within a given time number up to target amount
  def probability_of_actuated({ intent_about, { :times, target_number }, time_period } = _actuated) do
    actual_number = Memory.recall_intents_since(intent_about, time_period)
                    |> Enum.count()
    Logger.info(
      "#{actual_number} intents #{inspect intent_about} found out of target #{target_number} in #{inspect time_period}"
    )
    if target_number == 0, do: 1.0, else: min(1.0, actual_number / target_number)
  end

  # Calculate the probability that percepts a kind of actuated intents within a given time period validate a predicate
  def probability_of_actuated({ intent_about, predicate, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    fitting_intents = Enum.filter(intents, &(apply_predicate(predicate, &1, intents)))
    intents_count = Enum.count(intents)
    if intents_count == 0, do: 0, else: Enum.count(fitting_intents) / intents_count
  end

  @doc "Whether the model is currently believed in"
  def recall_believed?(model_name) do
    Memory.recall_believed?(model_name)
  end

  # TODO - cover for both atomic and mapped values

  defp apply_predicate({ :gt, val }, percept, _percepts) do
    percept.value > val
  end

  defp apply_predicate({ :abs_gt, val }, percept, _percepts) do
    abs(percept.value) > val
  end

  defp apply_predicate({ :lt, val }, percept, _percepts) do
    percept.value < val
  end

  defp apply_predicate({ :abs_lt, val }, percept, _percepts) do
    abs(percept.value) < val
  end

  defp apply_predicate({ :eq, val }, percept, _percepts) do
    percept.value == val
  end

  defp apply_predicate({ :neq, val }, percept, _percepts) do
    percept.value != val
  end

  defp apply_predicate({ :in, range }, percept, _percepts) do
    percept.value in range
  end

  defp apply_predicate({ :abs_in, range }, percept, _percepts) do
    abs(percept.value) in range
  end

  defp apply_predicate({ :gt, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) > val
  end

  defp apply_predicate({ :lt, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) < val
  end

  defp apply_predicate({ :eq, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) == val
  end

  defp apply_predicate({ :neq, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) != val
  end

  defp apply_predicate({ :in, attribute, range }, percept, _percepts) do
    Map.get(percept.value, attribute) in range
  end


  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:ascending, percept, percepts) do
    if Enum.count(percepts) > 1 do
      { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
      average = Enum.reduce(before, 0, &(&1.value + &2))
      percept.value > average
    else
      false
    end
  end

  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:descending, percept, percepts) do
    if Enum.count(percepts) > 1 do
      { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
      average = Enum.reduce(before, 0, &(&1.value + &2))
      percept.value < average
    else
      false
    end
  end


end