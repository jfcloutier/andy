defmodule Andy.Experience do
  @moduledoc """
  Responsible for learning which prediction fulfillments work best for each validator
  and having validators try the better ones more often than not.
  """

  require Logger
  alias Andy.{ PubSub, PredictionError, PredictionFulfilled, Fulfill }
  import Andy.Utils, only: [listen_to_events: 2]

  @name __MODULE__
  @experience_dir "experience"
  @experience_file "state.exs"

  @behaviour Andy.EmbodiedCognitionAgent

  # Act as if each fulfillment option succeeds a minimum of 1 out of ten times.
  @minimum 0.1

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the experience agent"
  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        # %{
        #    fulfillment_stats: %{} - %{validator_name: [{successes, failures}, nil, nil]} -- index in list == fulfillment index
        #    prediction_error_stats: %{} - %{conjecture_name: number of prediction errors}
        #  prediction_fulfilled_stats: %{} - %{conjecture_name: number of prediction fulfilled}
        #  }
        load_experience_state()
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  def load_experience_state() do
    path = experience_path()
    if File.exists?(path) do
      Logger.info("Experience loading saved state")
      { state, [] } = Code.eval_file(path)
      state
    else
      %{
        fulfillment_stats: %{ },
        prediction_error_stats: %{ },
        prediction_fulfilled_stats: %{ }
      }
    end
  end

  def save_experience_state(state) do
    Logger.info("Experience is saving its state")
    path = experience_path()
    if File.exists?(path) do
      ts = DateTime.utc_now
           |> to_string
           |> String.replace(" ", "T")
      File.cp(path, "#{path}_#{ts}")
    end
    File.write(experience_path(), inspect(state))
    state
  end

  defp experience_path() do
    File.mkdir_p(@experience_dir)
    "#{@experience_dir}/#{@experience_file}"
  end

  ### Cognition Agent Behaviour

  ## Handle timer events

  def handle_event({ :prediction_error, prediction_error }, state) do
    # Update fulfillment stats
    updated_state = update_fulfillment_stats(prediction_error, state)
    # Choose a fulfillment to correct the prediction error
    fulfillment_index = choose_fulfillment_index(prediction_error, updated_state)
    if fulfillment_index != nil do
      Logger.info("Experience chose fulfillment #{fulfillment_index} to address #{inspect prediction_error}")
      # Activate fulfillment
      PubSub.notify_fulfill(
        Fulfill.new(validator_name: prediction_error.validator_name, fulfillment_index: fulfillment_index)
      )
    else
      Logger.info("Experience chose no fulfillment to address #{inspect prediction_error}")
    end
    increment_prediction_error_count(updated_state, prediction_error)
  end

  def handle_event({ :prediction_fulfilled, prediction_fulfilled }, state) do
    update_fulfillment_stats(prediction_fulfilled, state)
    |> increment_prediction_fulfilled_count(prediction_fulfilled)
  end

  def handle_event(:shutdown, state) do
    save_experience_state(state)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # Update the fulfillment stats of a validator given a prediction error generated,
  # possibly when a fulfillment option is active
  defp update_fulfillment_stats(
         %PredictionError{
           validator_name: validator_name,
           fulfillment_index: fulfillment_index,
           fulfillment_count: fulfillment_count
         },
         state
       ) do
    learn_from_success_or_failure(
      validator_name,
      fulfillment_index,
      fulfillment_count,
      :failure,
      state
    )
  end

  # Update the fulfillment stats of a validator given a prediction fulfillment generated,
  # possibly when a fulfillment option is active
  defp update_fulfillment_stats(
         %PredictionFulfilled{
           validator_name: validator_name,
           fulfillment_index: fulfillment_index,
           fulfillment_count: fulfillment_count
         },
         state
       )  do
    learn_from_success_or_failure(
      validator_name,
      fulfillment_index,
      fulfillment_count,
      :success,
      state
    )
  end

  # Learn from the fulfillment success or failure of a validator by updating success/failure stats
  defp learn_from_success_or_failure(
         validator_name,
         fulfillment_index,
         fulfillment_count,
         success_or_failure,
         %{ fulfillment_stats: fulfillment_stats } = state
       ) do
    Logger.info(
      "Fulfillment data = #{inspect { fulfillment_index, fulfillment_count } } from validator #{validator_name}"
    )
    # The validator has an active fulfillment we are learning about
    new_validator_stats = case Map.get(fulfillment_stats, validator_name) do
      nil ->
        initial_validator_stats = List.duplicate({ 0, 0 }, fulfillment_count)
        Logger.info("New validator stats = #{inspect initial_validator_stats}")
        capture_success_or_failure(
          initial_validator_stats,
          fulfillment_index,
          success_or_failure,
          validator_name
        )
      validator_stats ->
        capture_success_or_failure(
          validator_stats,
          fulfillment_index,
          success_or_failure,
          validator_name
        )
    end
    updated_fulfillment_stats = Map.put(fulfillment_stats, validator_name, new_validator_stats)
    %{ state | fulfillment_stats: updated_fulfillment_stats }
  end

  defp capture_success_or_failure(
         validator_stats,
         nil,
         _success_or_failure,
         _validator_name
       ) do
    validator_stats
  end

  # Update success/failure stats
  defp capture_success_or_failure(
         validator_stats,
         fulfillment_index,
         success_or_failure,
         validator_name
       ) do
    stats = Enum.at(validator_stats, fulfillment_index)
    updated_validator_stats = List.replace_at(
      validator_stats,
      fulfillment_index,
      increment(stats, success_or_failure)
    )
    Logger.info("Validator stats for #{validator_name}: #{inspect updated_validator_stats}")
    updated_validator_stats
  end

  defp increment({ successes, failures }, :success) do
    { successes + 1, failures }
  end

  defp increment({ successes, failures }, :failure) do
    { successes, failures + 1 }
  end

  # Returns the index of a fulfillment option for a prediction, favoring the more successful ones,
  # or returns nil if no option is available
  defp choose_fulfillment_index(
         %{
           validator_name: validator_name,
           fulfillment_count: fulfillment_count
         } = _prediction_error,
         %{ fulfillment_stats: fulfillment_stats } = _state
       ) do
    if fulfillment_count == 0 do
      nil
    else
      # A fulfillment option is always given a minimum, non-zero probability of being selected
      # It corresponds to considering any option as succeeding at least some percent of the time
      # no matter what the stats say
      ratings = for { successes, failures } <- Map.get(fulfillment_stats, validator_name, []) do
        if successes == 0, do: @minimum, else: max(successes / (successes + failures), @minimum)
      end
      #    Logger.info("Ratings = #{inspect ratings} given stats #{inspect fulfillment_stats} for validator #{validator_name}")
      if Enum.count(ratings) == 0 do
        nil
      else
        ratings_sum = Enum.reduce(ratings, 0.0, fn (r, acc) -> r + acc end)
        spreads = Enum.map(ratings, &(&1 / ratings_sum))
        { ranges_reversed, _ } = Enum.reduce(
          spreads,
          { [], 0 },
          fn (spread, { ranges_acc, top_acc }) ->
            { [top_acc + spread | ranges_acc], top_acc + spread }
          end
        )
        ranges = Enum.reverse(ranges_reversed)
        random = Enum.random(1..1000) / 1000
        Enum.find(0..Enum.count(ranges) - 1, &(random < Enum.at(ranges, &1)))
      end
    end
  end

  defp increment_prediction_error_count(
         %{ prediction_error_stats: stats } = state,
         %PredictionError{
           prediction_name: prediction_name
         } = _prediction_error
       ) do
    count = Map.get(stats, prediction_name, 0)
    updated_stats = Map.put(stats, prediction_name, count + 1)
    %{ state | prediction_error_stats: updated_stats }
  end

  defp increment_prediction_fulfilled_count(
         %{ prediction_fulfilled_stats: stats } = state,
         %PredictionFulfilled{
           prediction_name: prediction_name
         } = _prediction_fulfilled
       ) do
    count = Map.get(stats, prediction_name, 0)
    updated_stats = Map.put(stats, prediction_name, count + 1)
    %{ state | prediction_fulfilled_stats: updated_stats }
  end

end