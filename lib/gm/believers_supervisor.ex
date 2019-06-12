defmodule Andy.GM.BelieversSupervisor do
  @moduledoc "Supervisor of all generative models and detectors"

  @name __MODULE__
  use DynamicSupervisor

  alias Andy.GM.{GenerativeModel, GenerativeModelDef, Detector}
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

  @doc "Start a generative model"
  def start_generative_model(%GenerativeModelDef{} = generative_model_def) do
    DynamicSupervisor.start_child(@name, {GenerativeModel, [generative_model_def]})
  end

  @doc "Start a detector"
  def start_detector(device, sense) do
    DynamicSupervisor.start_child(@name, {Detector, [device, sense]})
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end