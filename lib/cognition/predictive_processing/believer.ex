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
          validation: %{ }, # prediction_name => true|false
          predictors: [],
          for_predictors: MapSet.new()
        }
      end,
      [name: generative_model.name]
    )
    Task.async(fn -> start_predictors(pid) end)
    PubSub.notify_believer_started(generative_model.name)
    Logger.info("#{__MODULE__} started on generative model #{generative_model.name}")
    { :ok, pid }
  end

  @doc "Get the name of a believer given it's process id"
  def name(agent_pid) do
    model_name(agent_pid)
  end

  @doc "Get the name of a believer's model given it's process id"
  def model_name(agent_pid) do
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
      PubSub.notify_believer_terminated(model_name(believer_id))
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
            PredictorsSupervisor.start_predictor(prediction, believer_pid, model.name)
          end
        )
        validations = Enum.reduce(
          model.predictions,
          %{ },
          fn (prediction, acc) ->
            Map.put(acc, prediction.name, true)
          end
        )
        %{ state | predictors: predictor_pids, validations: validations }
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

  defp process_prediction_error(prediction_error, %{ validations: validations } = state) do
    PubSub.notify_believed(Belief.new(state.model.name, false))
    %{ state | validations: Map.put(validations, prediction_error.prediction_name, false) }
  end

  defp process_prediction_fulfilled(prediction_fulfilled, %{ validations: validations } = state state) do
    was_validated? = validated?(state)
    PubSub.notify_believed(Belief.new(state.model.name, true))
    new_state = %{ state | validations: Map.put(validations, prediction_fulfilled.prediction_name, true) }
    if not was_validated? and validated?(new_state) do
      PubSub.notify_believed(Belief.new(state.model.name, true))
      # TODO - Have BelieversSupervisor terminate self (and predictors) if transient (action-initiated)
    end
    new_state
  end

  defp validated?(%{ validations: validations } = state) do
    Enum.all?(validations, fn ({ _, value }) -> value end)
  end

end