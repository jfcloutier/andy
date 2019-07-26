defmodule Andy.ActuatorsSupervisor do
  @moduledoc "Supervisor of dynamically started actuators"

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.Actuator
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @doc "Start the actuators supervisor, linking it to its parent supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  @doc "Start an actuator on a configuration, linking it to this supervisor"
  def start_actuator(actuator_conf) do
    spec = {Actuator, [actuator_conf]}
    {:ok, _pid} = DynamicSupervisor.start_child(@name, spec)
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
