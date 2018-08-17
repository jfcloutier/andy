defmodule Andy.Experience do
  @moduledoc """
  Responsible for learning which prediction fulfillments work best
  and trying the better ones more often.
  """

  require Logger
  alias Andy.{ PubSub, Predictor, PredictionError, PredictionFulfilled, Fulfill }
  import Andy.Utils, only: [listen_to_events: 2]

  @name __MODULE__

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          # %{predictor_name: [{successes, failures}, nil, nil]} -- index in list == fulfillment index
          fulfillment_stats: %{}
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    {:ok, pid}
  end

  ### Cognition Agent Behaviour

   ## Handle timer events

  def handle_event({ :prediction_error, prediction_error }, state) do
    # Update fulfillment stats
    updated_state = update_fulfillment_stats(prediction_error, state)
    # Choose a fulfillment to correct the prediction error
    fulfillment_index = choose_fulfillment_index(prediction_error, state)
    Logger.info("Experience chose fulfillment #{fulfillment_index} to address #{inspect prediction_error}")
    # Activate fulfillment
    PubSub.notify_fulfill(
      Fulfill.new(predictor_name: prediction_error.predictor_name, fulfillment_index: fulfillment_index)
    )
    updated_state
  end

  def handle_event({ :prediction_fulfilled, predictor_name }, state) do
    update_fulfillment_stats(predictor_name, state)
  end


  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  defp update_fulfillment_stats(
         %PredictionError{ predictor_name: predictor_name },
         state
       ) do
    learn(predictor_name, :failure, state)
  end

  defp update_fulfillment_stats(
         %PredictionFulfilled{predictor_name: predictor_name},
         state
       )  do
    learn(predictor_name, :success, state)
  end

  defp learn(
         predictor_name,
         success_or_failure,
         %{ fulfillment_stats: fulfillment_stats } = state
       ) do
    { fulfillment_index, fulfillment_count } = Predictor.fulfillment_data(predictor_name)
    if fulfillment_index != nil do
      # The predictor has an active fulfillment we are learning about
      new_predictor_stats = case Map.get(fulfillment_stats, predictor_name) do
        nil ->
          predictor_stats = List.duplicate({ 0, 0 }, fulfillment_count)
                            |> List.replace_at(fulfillment_index, increment({ 0, 0 }, success_or_failure))
        predictor_stats ->
          { successes, failures } = Enum.at(predictor_stats, fulfillment_index)
          List.replace_at(predictor_stats, fulfillment_index, increment({ successes, failures }, success_or_failure))
      end
      updated_fulfillment_stats = Map.put(fulfillment_stats, predictor_name, new_predictor_stats)
      %{ state | fulfillment_stats: updated_fulfillment_stats }
    else
      # Nothing to learn
      state
    end
  end

  defp increment({ successes, failures }, :success) do
    { successes + 1, failures }
  end

  defp increment({ successes, failures }, :failure) do
    { successes, failures + 1 }
  end

  # Returns a number between 1 and the number of alternative fulfillments a prediction has (inclusive)
  defp choose_fulfillment_index(
         %{ predictor_name: predictor_name } = _prediction_error,
         %{ fulfillment_stats: fulfillment_stats } = _state
       ) do
    ratings = for { successes, failures } <- Map.get(fulfillment_stats, predictor_name, []) do
      # A fulfillment has a 10% minimum probability of being selected
      if successes == 0, do: 0.1, else: max(successes / (successes + failures), 0.1)
    end
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
    Enum.find(1..Enum.count(ranges), &(random < Enum.at(ranges, &1 - 1)))
  end

end