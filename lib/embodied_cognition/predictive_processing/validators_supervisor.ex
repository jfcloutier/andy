defmodule Andy.ValidatorsSupervisor do
  @moduledoc "Supervisor of dynamically started validators"

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.Validator
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @doc "Start the validators supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Starts validator if not already started. Returns validator name"
  def start_validator(prediction, believer_name, conjecture_name) do
    spec = {Validator, [prediction, believer_name, conjecture_name]}
    validator_name = Validator.validator_name(prediction, conjecture_name)

    :ok =
      case DynamicSupervisor.start_child(@name, spec) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          Logger.info("Validator #{validator_name} is already started")
          Validator.reset(validator_name)
          :ok

        other ->
          other
      end

    validator_name
  end

  @doc "Terminates validator if not already terminated."
  def terminate_validator(validator_name) do
    pid = Process.whereis(validator_name)

    if pid == nil do
      Logger.warn("Validator #{validator_name} already terminated")
    else
      Validator.about_to_be_terminated(validator_name)

      if DynamicSupervisor.terminate_child(@name, pid) == :ok do
        Logger.info("Terminated validator #{validator_name}")
      end
    end

    :ok
  end
end
