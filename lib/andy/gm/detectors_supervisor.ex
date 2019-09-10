defmodule Andy.GM.DetectorsSupervisor do
  @moduledoc "Supervisor of all detectors"

  @name __MODULE__
  use DynamicSupervisor

  alias Andy.GM.{Detector}
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @doc "Start the detectors supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  @doc "Start a detector"
  def start_detector(device, sense) do
    Logger.info("Starting detector on device #{inspect device} with sense #{inspect sense}")
    DynamicSupervisor.start_child(@name, {Detector, [device, sense]})
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
