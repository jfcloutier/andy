defmodule Andy.Ev3.Brick do

  require Logger
  @mountable "/dev/mmcblk0p4"

  def start() do
    Logger.info("Starting EV3 system")
    # Initialize
    load_ev3_modules()
    init_alsa()
    redirect_logging()
    # Define workers and child supervisors to be supervised
    children = [
    #  worker(Andy.Ev3.Display, []),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Andy.Ev3.BrickSupervisor]
    Supervisor.start_link(children, opts)
  end

  def ready?() do
    ipaddr() != "Unknown"
  end

  def ipaddr() do
    case Nerves.NetworkInterface.settings("wlan0") do
      { :ok, settings } -> settings.ipv4_address
      _ -> "Unknown"
    end
  end

  ### PRIVATE

  defp init_alsa() do
    :os.cmd('alsactl restore')
  end

  defp load_ev3_modules() do
    :os.cmd('modprobe suart_emu')
    :os.cmd('modprobe legoev3_ports')
    :os.cmd('modprobe snd_legoev3')
    :os.cmd('modprobe legoev3_battery')
  end

  defp redirect_logging() do
    :ok = maybe_mount_appdata()
    Logger.add_backend { LoggerFileBackend, :error }
    Logger.configure_backend { LoggerFileBackend, :error },
                             path: "/mnt/system.log",
                             level: :info
#    Logger.remove_backend :console

    # Turn off kernel logging to the console
    #System.cmd("dmesg", ["-n", "1"])
  end

  defp format_appdata() do
    case System.cmd("mke2fs", ["-t", "ext4", "-L", "APPDATA", "/dev/mmcblk0p4"]) do
      { _, 0 } -> :ok
      _ -> :error
    end
  end

  defp maybe_mount_appdata() do
    if !File.exists?("/mnt/.initialized") do
      mount_appdata()
    else
      :ok
    end
  end

  defp mount_appdata() do
    case System.cmd("mount", ["-t", "ext4", @mountable, "/mnt"]) do
      { _, 0 } ->
        File.write("/mnt/.initialized", "Done!")
        :ok
      _ ->
        :error
    end
  end

end
