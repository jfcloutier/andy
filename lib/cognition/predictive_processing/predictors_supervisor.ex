defmodule Andy.PredictorsSupervisor do
  @moduledoc "Supervisor of dynamically started predictors"

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.Predictor
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

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts predictor if not already started."
  def start_predictor(prediction, believer_name, model_name) do
    spec = { Predictor, [prediction, believer_name, model_name] }
    :ok = case DynamicSupervisor.start_child(@name, spec) do
      { :ok, _pid } -> :ok
      { :error, { :already_started, _pid } } -> :ok
      other -> other
    end
  end

  @doc "Terminates predictor if not already terminated."
  def terminate_predictor(predictor_name) do
    Predictor.about_to_be_terminated(predictor_name)
    if DynamicSupervisor.terminate_child(@name, predictor_name) == :ok do
      Logger.info("Terminated predictor #{predictor_name}")
    end
    :ok
  end

end