defmodule Andy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @poll_runtime_delay 60_000
  @max_waits 20


  use Application
  require Logger
  alias Andy.{ CognitionSupervisor, PubSub, InternalClock, Speaker }
  import Supervisor.Spec

  def start(_type, _args) do
    Logger.info("Starting #{__MODULE__}")
    Logger.info("SYSTEM is #{Andy.system()}")
    Logger.info("PLATFORM is #{Andy.platform()}")
    Logger.info("PROFILE is #{Andy.profile()}")
    Andy.start_platform()
    wait_for_platform_ready(0)
    children = [
      supervisor(AndyWeb.Endpoint, []),
      supervisor(CognitionSupervisor, []),
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

  @doc "Return ERTS runtime stats"
  def runtime_stats() do  # In camelCase for Elm's automatic translation
    stats = mem_stats(Andy.system())
    %{
      ramFree: stats.mem_free,
      ramUsed: stats.mem_used,
      swapFree: stats.swap_free,
      swapUsed: stats.swap_used
    }
  end

  @doc "Loop pushing runtime stats every @poll_runtime_delay seconds"
  def push_runtime_stats() do
    PubSub.notify_runtime_stats(runtime_stats())
    :timer.sleep(@poll_runtime_delay)
    push_runtime_stats()
  end

  @doc "Shut down the Prediction Processing"
  def shutdown() do
    PubSub.notify_shutdown()
  end

  def toggle_paused() do
    PubSub.toggle_paused()
  end

  def go() do
    spawn(fn () -> connect_to_nodes() end)
    CognitionSupervisor.start_cognition()
    spawn(fn -> push_runtime_stats() end)
  end

  ## PRIVATE

  defp wait_for_platform_ready(n) do
    if Andy.platform_ready?() do
      Process.sleep(1000) # TODO - necessary?
      Logger.info("Platform ready!")
      :ok
    else
      if n >= @max_waits do
        { :error, :platform_not_ready }
      else
        Logger.info("Platform not ready")
        Process.sleep(1_000)
        wait_for_platform_ready(n + 1)
      end
    end
  end

  defp connect_to_nodes() do
    Node.connect(Andy.peer()) # try to join the peer network
    if Node.list() == [] do
      Process.sleep(1_000)
      connect_to_nodes() # try again
    else
      Logger.info("#{Node.self()} is connected to #{inspect Node.list()}")
    end
  end

  defp mem_stats("ev3") do
    { res, 0 } = System.cmd("free", ["-m"])
    [_labels, mem, _buffers, swap | _] = String.split(res, "\n")
    [_, _mem_total, mem_used, mem_free, _, _, _] = String.split(mem)
    [_, _swap_total, swap_used, swap_free] = String.split(swap)
    %{
      mem_free: to_int!(mem_free),
      mem_used: to_int!(mem_used),
      swap_free: to_int!(swap_free),
      swap_used: to_int!(swap_used)
    }
  end

  defp mem_stats("pc") do
    { res, 0 } = System.cmd("free", ["-m"])
    [_labels, mem, swap, _buffers] = String.split(res, "\n")
    [_, _mem_total, mem_used, mem_free, _, _, _] = String.split(mem)
    [_, _swap_total, swap_used, swap_free] = String.split(swap)
    %{
      mem_free: to_int!(mem_free),
      mem_used: to_int!(mem_used),
      swap_free: to_int!(swap_free),
      swap_used: to_int!(swap_used)
    }
  end

  defp to_int!(s) do
    { i, _ } = Integer.parse(s)
    i
  end

end
