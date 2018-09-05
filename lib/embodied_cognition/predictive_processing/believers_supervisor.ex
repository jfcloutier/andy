defmodule Andy.BelieversSupervisor do
  @moduledoc " Supervisor of dynamically started believers"

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.{ Believer, Conjectures }
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

  @doc "Start a believer on a conjecture"
  def start_believer(conjecture) do
    spec = { Believer, [conjecture] }
    :ok = case DynamicSupervisor.start_child(@name, spec) do
      { :ok, _pid } -> :ok
      { :error, { :already_started, pid } } ->
        Believer.reset_validators(pid)
        :ok
      other -> other
    end
    conjecture.name
  end

  @doc " A validator enlists a believer"
  def enlist_believer(conjecture_name, validator_name, is_or_not) do
    Logger.info("Enlisting believer of conjecture #{conjecture_name} for validator #{validator_name}")
    conjecture = Conjectures.fetch!(conjecture_name)
    believer_name = start_believer(conjecture)
    Believer.enlisted_by_validator(believer_name, validator_name, is_or_not)
    # The name of the conjecture is also the name of its believer
    conjecture_name
  end

  @doc " A validator releases a believer by its conjecture name, which is its name"
  def release_believer(conjecture_name, validator_name) do
    Logger.info("Releasing believer of conjecture #{conjecture_name} from validator #{validator_name}")
    # A believer's name is that of its conjecture
    Believer.released_by_validator(conjecture_name, validator_name)
  end

  @doc "Terminate a believer"
  def terminate(believer_name) do
    pid = Process.whereis(believer_name)
    if pid == nil do
      Logger.warn("Believer #{believer_name} already terminated")
    else
      if DynamicSupervisor.terminate_child(@name, pid) == :ok do
        Logger.info("Terminated believer #{believer_name}")
      end
    end
    :ok
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end