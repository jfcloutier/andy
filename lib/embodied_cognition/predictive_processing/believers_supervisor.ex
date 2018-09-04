defmodule Andy.BelieversSupervisor do
  @moduledoc " Supervisor of dynamically started believers"

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

  @doc "Start the believers supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  @doc "Start a believer on a generative model"
  def start_believer(model) do
    spec = { Believer, [model] }
    :ok = case DynamicSupervisor.start_child(@name, spec) do
      { :ok, _pid } -> :ok
      { :error, { :already_started, pid } } ->
        Believer.reset_predictors(pid)
        :ok
      other -> other
    end
    model.name
  end

  @doc " A predictor enlists a believer"
  def enlist_believer(model_name, predictor_name, is_or_not) do
    Logger.info("Enlisting believer of model #{model_name} for predictor #{predictor_name}")
    model = GenerativeModels.fetch!(model_name)
    believer_name = start_believer(model)
    Believer.enlisted_by_predictor(believer_name, predictor_name, is_or_not)
    # The name of the model is also the name of its believer
    model_name
  end

  @doc " A predictor releases a believer by its model name, which is its name"
  def release_believer(model_name, predictor_name) do
    Logger.info("Releasing believer of model #{model_name} from predictor #{predictor_name}")
    # A believer's name is that of its model
    Believer.released_by_predictor(model_name, predictor_name)
  end

  @doc "Terminate a believer"
  def terminate(believer_name) do
    pid = Process.whereis(believer_name)
    if pid == nil do
      Logger.warn("Believer #{believer_name} already terminated")
    else
      if DynamicSupervisor.terminate_child(@name, pid) == :ok do
        Logger.info("Terminated believer #{believer_name}")
      end
    end
    :ok
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end