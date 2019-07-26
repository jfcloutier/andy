defmodule Andy.GM.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @max_waits 20

  use Application
  require Logger
  alias Andy.GM.{EmbodiedCognitionSupervisor}
  alias Andy.Speaker
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
      supervisor(AndyWeb.Endpoint, []),
      supervisor(EmbodiedCognitionSupervisor, []),
      Speaker
    ]

    opts = [strategy: :one_for_one, name: :andy_supervisor]
    result = Supervisor.start_link(children, opts)
    go()
    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    AndyWeb.Endpoint.config_change(changed, removed)
    :ok
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
