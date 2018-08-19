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

  def start_predictor(prediction, believer_name, model_name) do
    spec = { Predictor, [prediction, believer_name, model_name] }
    { :ok, _pid } = DynamicSupervisor.start_child(@name, spec)
  end

  def terminate_predictor(predictor_name) do
    Logger.info("Terminating predictor #{predictor_name}")
    Predictor.about_to_be_terminated(predictor_name)
    DynamicSupervisor.terminate_child(@name, predictor_name)
  end

  def start_predictor_if_not_started(
        prediction,
        believer_name,
        model_name
      ) do
    predictor_name = Predictor.predictor_name(prediction, model_name)
    if not predictor_started?(predictor_name) do
      start_predictor(prediction, believer_name, model_name)
    end
    predictor_name
  end

  def terminate_predictor_if_started(
        prediction,
        model_name
      ) do
    predictor_name = Predictor.predictor_name(prediction, model_name)
    if predictor_started?(predictor_name) do
      terminate_predictor(predictor_name)
    end
    predictor_name
  end

  defp predictor_started?(predictor_name) do
    Enum.any?(
      DynamicSupervisor.which_children(@name),
      fn ({ _, pid, _, _ }) ->
        Predictor.has_name?(pid, predictor_name)
      end
    )
  end

end