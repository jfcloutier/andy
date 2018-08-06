defmodule Andy.Believer do

  @moduledoc "Given a generative model, updates belief in it upon prediction errors."

  require Logger
  alias Andy.{ PubSub, Belief }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([generative_model]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [generative_model] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(generative_model) do
    { :ok, pid } = Agent.start_link(
      fn () ->
        register_internal()
        %{
          model: generative_model,
          belief: Belief.new(generative_model.name),
          predictors: [],
          for_predictors: MapSet.new()
        }
      end,
      [name: generative_model.name]
    )
    Task.async(fn -> start_predictors(pid) end)
    Logger.info("#{__MODULE__} started on generative model #{generative_model.name}")
    { :ok, pid }
  end

  @doc "Get the name of a believer given it's process id"
  def name(agent_pid) do
    Agent.get(
      agent_pid,
      fn (%{ model: generative_model }) ->
        generative_model.name
      end
    )
  end

  @doc "A believer was pressed into duty by a predictor"
  def grabbed_by_predictor(believer_pid, predictor_pid) do
    Agent.update(
      believer_pid,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: MapSet.put(for_predictors, predictor_pid) }
      end
    )
  end

  @doc "A believer was released by a predictor"
  def released_by_predictor(believer_pid, predictor_pid) do
    Agent.update(
      believer_pid,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: MapSet.delete(for_predictors, predictor_pid) }
      end
    )
    if obsolete?(believer_pid) do
      terminate_predictors(believer_pid)
      BelieversSupervisor.terminate(believer_pid)
    end
  end


  @doc "Is a believer not needed anymore?"
  def obsolete?(believer_pid) do
    Agent.get(
      believer_pid,
      fn (%{ for_predictors: for_predictors, model: model }) ->
        not model.hyper_prior? and MapSet.size(for_predictors) == 0
      end
    )
  end

  @doc "Start a predictor for each prediction in the model"
  def start_predictors(believer_pid) do
    Agent.update(
      believer_pid,
      fn (%{ model: model } = state) ->
        predictor_pids = Enum.map(
          model.predictions,
          fn (prediction) ->
            PredictorsSupervisor.start_predictor(prediction, believer_pid)
          end
        )
        %{ state | predictors: predictor_pids }
      end
    )
  end

  def believes?(believer_pid, precision) do
    Agent.get(
      believer_pid,
      fn (%{ belief: belief }) ->
        in_acceptable_range?(belief.probability, precision)
      end
    )
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  def handle_event(
        { :prediction_error, %{ model_name: model_name } = prediction_error },
        %{
          model: model
        } = state
      ) when model.name == model_name do
    process_prediction_error(prediction_error, state)
    state
  end

  def handle_event(
        { :prediction_fulfilled, %{ model_name: model_name } = prediction_fulfilled },
        %{
          model: model
        } = state
      ) when model_name == model.name do
    process_prediction_fulfilled(prediction_fulfilled, state)
    state
  end


  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  # PRIVATE

  defp terminate_predictors(believer_pid) do
    Agent.update(
      believer_id,
      fn (%{ predictors: predictor_ids }) ->
        Enum.each(
          predictor_ids,
          &(PredictorsSupervisor.terminate(&1))
        )
      end
    )
  end

  defp process_prediction_error(prediction_error, state) do
    # TODO
    # Select and schedule (faster if high focus) having the associated predictor try a fulfillment
    # Revise belief, notify of Belief if changed
    # Somehow alter the effective precision of competing predictors
    state
  end

  defp process_prediction_fulfilled(prediction_fulfilled, state) do
    # TODO
    # Revise belief, notifiy if Belief changed
    # Somehow un-alter the effective precision of competing predictors
    # If for transient model (from action), terminate self
  end

end