defmodule Andy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @target Mix.Project.config()[:target]

  use Application

  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    if System.get_env("MIX_TARGET") == "ev3", do: initialize_ev3()
    opts = [strategy: :one_for_one, name: Andy.Supervisor]
    Supervisor.start_link(children(@target), opts)
  end

  # List all child processes to be supervised
  def children("host") do
    [
      # Starts a worker by calling: Andy.Worker.start_link(arg)
      # {Andy.Worker, arg},
    ]
  end

  def children(_target) do
    [
      # Starts a worker by calling: Andy.Worker.start_link(arg)
      # {Andy.Worker, arg},
    ]
  end

  defp initialize_ev3() do
    :os.cmd('modprobe suart_emu')
    :os.cmd('modprobe legoev3_ports')
    :os.cmd('modprobe snd_legoev3')
    :os.cmd('modprobe legoev3_battery')
  end

end
