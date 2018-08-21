defmodule Andy.BelieversSupervisor do
  @moduledoc " Supervisor of dynamically started believer."

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.{ Believer, GenerativeModels }
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] },
      type: :supervisor
    }
  end

  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  def start_believer(model) do
    spec = { Believer, [model] }
    :ok = case DynamicSupervisor.start_child(@name, spec) do
      { :ok, _pid } -> :ok
      { :error, { :already_started, _pid } } -> :ok
      other -> other
    end
    model.name
  end

  @doc " A predictor grabs a believer"
  def grab_believer(model_name, predictor_name, is_or_not) do
    Logger.info("Grabbing believer of model #{model_name} for predictor #{predictor_name}")
    model = GenerativeModels.model_named(model_name)
    believer_name = start_believer(model)
    Believer.grabbed_by_predictor(believer_name, predictor_name, is_or_not)
    # The name of the model is also the name of its believer
    model_name
  end

  @doc " A predictor releases a believer by its model name"
  def release_believer(model_name, predictor_name) do
    Logger.info("Releasing believer of model #{model_name} from predictor #{predictor_name}")
    # A believer's name is that of its model
    Believer.released_by_predictor(model_name, predictor_name)
  end

  @doc " A predictor releases a believer by its name"
  def release_believer_named(believer_name, predictor_name) do
    Believer.released_by_predictor(believer_name, predictor_name)
  end

  def terminate(believer_name) do
    if DynamicSupervisor.terminate_child(@name, believer_name) == :ok do
      Logger.info("Terminated believer #{believer_name}")
    end
    :ok
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end