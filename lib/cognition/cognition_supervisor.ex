defmodule Andy.CognitionSupervisor do

  use Supervisor
  require Logger
  alias Andy.{ PubSub, Memory, DetectorsSupervisor, ActuatorsSupervisor, BelieversSupervisor,
               InternalClock, PG2Communicator,
               RESTCommunicator, GenerativeModels, Attention }

  @name __MODULE__

  ### Supervisor Callbacks

  @doc "Start the supervisor, linking it to its parent supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    { :ok, _pid } = Supervisor.start_link(__MODULE__, [], name: @name)
  end

  def init(_) do
    children = [
      PubSub,
      Memory,
      PG2Communicator,
      RESTCommunicator,
      InternalClock,
      Attention,
      GenerativeModels,
      DetectorsSupervisor,
      ActuatorsSupervisor,
      PredictorsSupervisor,
      BelieversSupervisor
    ]
    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  @doc "Start predictive_processing processing"
  def start_cognition() do
    Logger.info("Starting embodied cognition")
    start_detectors()
    start_actuators()
    start_prior_believers()
  end

  ### Private

  defp start_detectors() do
    Logger.info("Starting detectors")
    for sensor <- Andy.sensors() do
      for sense <- Device.senses(sensor) do
        DetectorsSupervisor.start_detector(sensor, sense)
      end
    end
  end

  defp start_actuators() do
    Logger.info("Starting actuators")
    Andy.actuation_logic() # returns actuator configs
    |> Enum.each(&(ActuatorsSupervisor.start_actuator(&1)))
  end

  defp start_prior_believers() do
    Logger.info("Starting believers")
    GenerativeModels.hyper_prior_models()
    |> Enum.each(&(BelieversSupervisor.start_believer(&1)))
  end

end
	
