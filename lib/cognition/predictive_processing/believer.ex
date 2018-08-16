defmodule Andy.Believer do

  @moduledoc "Given a generative model, updates belief in it upon prediction errors."

  require Logger
  alias Andy.{ PubSub, Belief, BelieversSupervisor, PredictorsSupervisor }

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
    believer_name = generative_model.name
    { :ok, pid } = Agent.start_link(
      fn () ->
        register_internal()
        %{
          model: generative_model,
          validations: %{ }, # prediction_name => true|false -- the believer is validated if all prediction are true
          predictors: [], # predictor names
          for_predictors: MapSet.new()
          # predictor name
        }
      end,
      [name: believer_name]
    )
    Task.async(fn -> start_predictors(believer_name) end)
    PubSub.notify_believer_started(believer_name)
    Logger.info("#{__MODULE__} started on generative model #{generative_model.name}")
    { :ok, pid }
  end

  @doc "Get the name of a believer given it's process id"
  def name(believer_pid) do
    model_name(believer_pid)
  end

  @doc "Get the name of a believer's model given it's process id"
  def model_name(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ model: generative_model }) ->
        generative_model.name
      end
    )
  end


  @doc "A believer was pressed into duty by a predictor"
  def grabbed_by_predictor(believer_name, predictor_name) do
    Agent.update(
      believer_name,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: MapSet.put(for_predictors, predictor_name) }
      end
    )
  end

  @doc "A believer was released by a predictor"
  def released_by_predictor(believer_name, predictor_name) do
    Agent.update(
      believer_name,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: MapSet.delete(for_predictors, predictor_name) }
      end
    )
    if obsolete?(believer_name) do
      terminate_predictors(believer_name)
      BelieversSupervisor.terminate(believer_name)
      PubSub.notify_believer_terminated(believer_name)
    end
  end


  @doc "Is a believer not needed anymore?"
  def obsolete?(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ for_predictors: for_predictors, model: model }) ->
        not model.hyper_prior? and MapSet.size(for_predictors) == 0
      end
    )
  end

  @doc "Start a predictor for each prediction in the model"
  def start_predictors(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ model: model } = state) ->
        predictor_names = Enum.map(
          model.predictions,
          fn (prediction) ->
            PredictorsSupervisor.start_predictor(prediction, believer_name, model.name)
          end
        )
        validations = Enum.reduce(
          model.predictions,
          %{ },
          fn (prediction, acc) ->
            Map.put(acc, prediction.name, true)
          end
        )
        %{ state | predictors: predictor_names, validations: validations }
      end
    )
  end

  @doc "Are all of the model's predictions validated?"
  def believes?(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ validations: validations }) ->
        Enum.all?(validations, fn ({ _, value }) -> value end)
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
      ) do
    if  model.name == model_name do
      process_prediction_error(prediction_error, state)
    else
      state
    end
  end

  def handle_event(
        { :prediction_fulfilled, %{ model_name: model_name } = prediction_fulfilled },
        %{
          model: model
        } = state
      ) do
    if  model.name == model_name do
      process_prediction_fulfilled(prediction_fulfilled, state)
    else
      state
    end
  end


  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  # PRIVATE

  defp terminate_predictors(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ predictors: predictor_names }) ->
        Enum.each(
          predictor_names,
          &(PredictorsSupervisor.terminate(&1))
        )
      end
    )
  end

  defp process_prediction_error(prediction_error, %{ validations: validations } = state) do
    PubSub.notify_believed(Belief.new(state.model.name, false))
    %{ state | validations: Map.put(validations, prediction_error.prediction_name, false) }
  end

  defp process_prediction_fulfilled(prediction_fulfilled, %{ validations: validations } = state) do
    was_already_believed? = believes?(state)
    if not was_already_believed? do
      PubSub.notify_believed(Belief.new(state.model.name, true))
    end
    %{ state | validations: Map.put(validations, prediction_fulfilled.prediction_name, true) }
  end

end