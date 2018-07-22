defmodule Andy.PredictionProcessingSupervisor do

  use Supervisor
  require Logger
  alias Andy.{CNS, Memory, DetectorsSupervisor, ActuatorsSupervisor, InternalClock, PG2Communicator, RESTCommunicator}

  @name __MODULE__

  ### Supervisor Callbacks

  @doc "Start the smart thing supervisor, linking it to its parent supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    {:ok, _pid} = Supervisor.start_link(@name, [], [name: @name])
  end

  @spec init(any) :: {:ok, tuple}
  def init(_) do
    children = [
      worker(CNS, []),
      worker(Memory, []),
      worker(PG2Communicator, []),
      worker(RESTCommunicator, []),
      worker(InternalClock, []),
      supervisor(DetectorsSupervisor, []),
      supervisor(ActuatorsSupervisor, []),
    ]
    opts = [strategy: :one_for_one]
    supervise(children, opts)
  end

  @doc "Start embodied cognition"
  def start_embodied_cognition() do
    Logger.info("Starting embodied cognition")
    start_detectors()
    # TODO
  end


  ### Private

  defp start_detectors() do
    Logger.info("Starting detectors")
    sensing_devices = Andy.sensors() ++ Andy.motors()
    Enum.each(sensing_devices, &(DetectorsSupervisor.start_detector(&1)))
  end

  defp start_actuators() do
    Logger.info("Starting actuators")
    Andy.actuation_logic() # returns actuator configs
    |> Enum.each(&(ActuatorsSupervisor.start_actuator(&1)))
  end

end
	
