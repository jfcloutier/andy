defmodule Andy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @max_waits 20

  use Application
  require Logger
  alias Andy.GM.{EmbodiedCognitionSupervisor}
  alias Andy.{Speaker, AndyWorldGateway}
  import Supervisor.Spec

  def start(_type, _args) do
    Logger.info("Starting #{__MODULE__}")
    Logger.info("SYSTEM is #{Andy.system()}")
    Logger.info("PLATFORM is #{Andy.platform()}")
    # TODO - point to GM graph
    Logger.info("PROFILE is #{Andy.profile()}")
    Andy.start_platform()
    wait_for_platform_ready(0)

    children = [
      supervisor(EmbodiedCognitionSupervisor, []),
      Speaker
    ]

    # TODO - If platform is mock, add an AndyWorldProxy as child.
    # Make all calls to AndyWorld through it
    # Have it subscribe to PubSub events and cast them all to AndyWorld

    all_my_children = if Andy.simulation?(), do: children ++ [AndyWorldGateway], else: children

    opts = [strategy: :one_for_one, name: :andy_supervisor]
    result = Supervisor.start_link(all_my_children, opts)
    go()
    result
  end

  def go() do
    EmbodiedCognitionSupervisor.start_embodied_cognition()
  end

  ## PRIVATE

  defp wait_for_platform_ready(n) do
    if Andy.platform_ready?() do
      # TODO - necessary?
      Process.sleep(1000)
      Logger.info("Platform ready!")
      :ok
    else
      if n >= @max_waits do
        {:error, :platform_not_ready}
      else
        Logger.info("Platform not ready")
        Process.sleep(1_000)
        wait_for_platform_ready(n + 1)
      end
    end
  end
end
