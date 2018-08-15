def Andy.PredictorsSupervisor do
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
    DynamicSupervisor.start_link(@name, [] [name: @name])
  end

  def start_predictor(prediction, believer_name, model_name) do
    spec = { Predictor, [prediction, believer_name, model_name] }
    { :ok, _name } = DynamicSupervisor.start_child(@name, spec)
  end

  def terminate(predictor_name) do
    Predictor.about_to_be_terminated(predictor_name)
    DynamicSupervisor.terminate_child(@name, predictor_name)
  end

end