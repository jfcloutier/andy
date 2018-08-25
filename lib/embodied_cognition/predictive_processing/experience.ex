defmodule Andy.Experience do
  @moduledoc """
  Responsible for learning which prediction fulfillments work best for each predictor
  and having predictors try the better ones more often than not.
  """

  require Logger
  alias Andy.{ PubSub, PredictionError, PredictionFulfilled, Fulfill }
  import Andy.Utils, only: [listen_to_events: 2]

  @name __MODULE__

  @behaviour Andy.EmbodiedCognitionAgent

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
        %{
          # %{predictor_name: [{successes, failures}, nil, nil]} -- index in list == fulfillment index
          fulfillment_stats: %{ }
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
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
        Fulfill.new(predictor_name: prediction_error.predictor_name, fulfillment_index: fulfillment_index)
      )
    else
      Logger.info("Experience chose no fulfillment to address #{inspect prediction_error}")
    end
    updated_state
  end

  def handle_event({ :prediction_fulfilled, prediction_fulfilled }, state) do
    update_fulfillment_stats(prediction_fulfilled, state)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # Update the fulfillment stats of a predictor given a prediction error generated,
  # possibly when a fulfillment option is active
  defp update_fulfillment_stats(
         %PredictionError{
           predictor_name: predictor_name,
           fulfillment_index: fulfillment_index,
           fulfillment_count: fulfillment_count
         },
         state
       ) do
    learn_from_success_or_failure(
      predictor_name,
      fulfillment_index,
      fulfillment_count,
      :failure,
      state
    )
  end

  # Update the fulfillment stats of a predictor given a prediction fulfillment generated,
  # possibly when a fulfillment option is active
  defp update_fulfillment_stats(
         %PredictionFulfilled{
           predictor_name: predictor_name,
           fulfillment_index: fulfillment_index,
           fulfillment_count: fulfillment_count
         },
         state
       )  do
    learn_from_success_or_failure(
      predictor_name,
      fulfillment_index,
      fulfillment_count,
      :success,
      state
    )
  end

  # Learn from the fulfillment success or failure of a predictor by updating success/failure stats
  defp learn_from_success_or_failure(
         predictor_name,
         fulfillment_index,
         fulfillment_count,
         success_or_failure,
         %{ fulfillment_stats: fulfillment_stats } = state
       ) do
    Logger.info(
      "Fulfillment data = #{inspect { fulfillment_index, fulfillment_count } } from predictor #{predictor_name}"
    )
    # The predictor has an active fulfillment we are learning about
    new_predictor_stats = case Map.get(fulfillment_stats, predictor_name) do
      nil ->
        initial_predictor_stats = List.duplicate({ 0, 0 }, fulfillment_count)
        Logger.info("New predictor stats = #{inspect initial_predictor_stats}")
        capture_success_or_failure(initial_predictor_stats, fulfillment_index, success_or_failure)
      predictor_stats ->
        Logger.info("Prior predictor stats = #{inspect predictor_stats}")
        capture_success_or_failure(predictor_stats, fulfillment_index, success_or_failure)
    end
    updated_fulfillment_stats = Map.put(fulfillment_stats, predictor_name, new_predictor_stats)
    %{ state | fulfillment_stats: updated_fulfillment_stats }
  end

  defp capture_success_or_failure(predictor_stats, nil, _success_or_failure) do
    predictor_stats
  end

  # Update success/failure stats
  defp capture_success_or_failure(predictor_stats, fulfillment_index, success_or_failure) do
    stats = Enum.at(predictor_stats, fulfillment_index)
    List.replace_at(predictor_stats, fulfillment_index, increment(stats, success_or_failure))
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
         %{ predictor_name: predictor_name } = _prediction_error,
         %{ fulfillment_stats: fulfillment_stats } = _state
       ) do
    ratings = for { successes, failures } <- Map.get(fulfillment_stats, predictor_name, []) do
      # A fulfillment has a 10% minimum probability of being selected
      if successes == 0, do: 0.1, else: max(successes / (successes + failures), 0.1)
    end
    Logger.info("Ratings = #{inspect ratings} given stats #{inspect fulfillment_stats} for predictor #{predictor_name}")
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