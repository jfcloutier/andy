defmodule Andy.Ev3.Brick do

  require Logger

  def start() do
    import Supervisor.Spec
    Logger.info("Starting EV3 system")
    # Initialize
    load_ev3_modules()
    start_writable_fs()
    init_alsa()
    # Define workers and child supervisors to be supervised
    children = [
      worker(Andy.Ev3.Display, []),
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
    Logger.add_backend { LoggerFileBackend, :error }
    Logger.configure_backend { LoggerFileBackend, :error },
                             path: "/mnt/system.log",
                             level: :info
    Logger.remove_backend :console

    # Turn off kernel logging to the console
    #System.cmd("dmesg", ["-n", "1"])
  end

  defp format_appdata() do
    case System.cmd("mke2fs", ["-t", "ext4", "-L", "APPDATA", "/dev/mmcblk0p3"]) do
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
    case System.cmd("mount", ["-t", "ext4", "/dev/mmcblk0p3", "/mnt"]) do
      { _, 0 } ->
        File.write("/mnt/.initialized", "Done!")
        :ok
      _ ->
        :error
    end
  end

  defp start_writable_fs() do
    case maybe_mount_appdata() do
      :ok ->
        redirect_logging()
      :error ->
        case format_appdata() do
          :ok ->
            mount_appdata()
            redirect_logging()
          error -> error
        end
    end
  end

end
