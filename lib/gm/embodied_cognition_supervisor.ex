defmodule Andy.GM.EmbodiedCognitionSupervisor do
  @moduledoc """
  The supervisor in charge of singular embodied cognition agents
  and of the supervisors of dynamically started embodied cognition agents
  """

  use Supervisor
  require Logger
  alias Andy.GM.{PubSub, CognitionDef, BelieversSupervisor}
  alias Andy.{ ActuatorsSupervisor, InternalClock, Device }

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
      InternalClock,
      ActuatorsSupervisor,
      BelieversSupervisor
    ]
    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end

  @doc "Start embodied cognition"
  def start_embodied_cognition() do
    spawn(
      fn ->
        Process.sleep(5000)
        Andy.BrickPi.LegoSound.speak("Ready")
        Process.sleep(2000)
        Logger.info("*** STARTING EMBODIED COGNITION ***")
        start_detectors()
        start_actuators()
        start_generative_models()
        InternalClock.resume()
      end
    )
  end

  ### Private

  # Start a (not-yet-polling) detector for each sense of each sensor
  defp start_detectors() do
    Logger.info("Starting detectors")
    for sensor <- Andy.sensors() do
      for sense <- Device.senses(sensor) do
        BelieversSupervisor.start_detector(sensor, sense)
      end
    end
  end

  # Start an actuator for each mind of actuation (locomotion, sound, lights etc.)
  defp start_actuators() do
    Logger.info("Starting actuators")
    Andy.actuation_logic() # returns actuator configs
    |> Enum.each(&(ActuatorsSupervisor.start_actuator(&1)))
  end

  # Start and activate all generative models
  defp start_generative_models() do
    Logger.info("Starting generative models")
    Andy.cognition_def()
    |> CognitionDef.generative_model_defs_with_sub_believers()
    |> Enum.each(&(BelieversSupervisor.start_generative_model(&1)))
  end

end

