defmodule Andy.DetectorsSupervisor do
  @moduledoc "Supervisor of dynamically started detectors"

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.Detector
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] },
      type: :supervisor
    }
  end

  @doc "Start the detectors supervisor, linking it to its parent supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  @doc "Start a supervised detector worker for a sensing device"
  def start_detector(sensing_device) do
    #		Logger.debug("Starting Detector on #{sensing_device.path}")
    spec = { Detector, [sensing_device] }
    { :ok, _pid } = DynamicSupervisor.start_child(@name, spec)
  end

  ## Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end
