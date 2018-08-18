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
  def start_detector(sensing_device, sense) do
    #		Logger.debug("Starting Detector on #{sensing_device.path} for sense #{sense}")
    spec = { Detector, [sensing_device, sense] }
    { :ok, _pid } = DynamicSupervisor.start_child(@name, spec)
  end

  def set_polling_priority(detector_specs, priority) do
    # Find all detectors that match and set their polling priority
    # and call Detector.set_polling_priority(detector_pid, priority)
    for {_, detector_pid, _, _} <- DynamicSupervisor.which_children(@name) do
      if Detector.detects?(detector_pid, detector_specs) do
        Detector.set_polling_priority(detector_pid, priority)
      end
    end
    :ok
  end

  ## Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end
