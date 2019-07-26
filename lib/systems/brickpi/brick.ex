defmodule Andy.BrickPi.Brick do
  require Logger
  alias Andy.Device
  alias Andy.BrickPi.{LegoSensor, LegoMotor}

  @ports_path "/sys/class/lego-port"

  def start() do
    Logger.info("Starting BrickPi system")
    redirect_logging()
    initialize_brickpi_ports()
    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
  end

  def ready?() do
    true
  end

  ### PRIVATE

  defp redirect_logging() do
    Logger.add_backend({LoggerFileBackend, :error})

    Logger.configure_backend({LoggerFileBackend, :error},
      path: "brickpi.log",
      level: :info
    )

    #    Logger.remove_backend :console

    # Turn off kernel logging to the console
    # System.cmd("dmesg", ["-n", "1"])
  end

  defp initialize_brickpi_ports() do
    Enum.each(
      Andy.ports_config(),
      fn %{port: port_name, device: device_type} ->
        set_brickpi_port(port_name, device_type)
      end
    )
  end

  @doc "Associate a BrickPi port with an BrickPi motor or sensor"
  def set_brickpi_port(port, device_type) do
    if (port in [:in1, :in2, :in3, :in4] and LegoSensor.sensor?(device_type)) or
         (port in [:outA, :outB, :outC, :outD] and LegoMotor.motor?(device_type)) do
      port_path = "#{@ports_path}/port#{brickpi_port_number(port)}"
      device_mode = Andy.device_mode(device_type)
      device_code = Andy.device_code(device_type)
      Logger.info("#{port_path}/mode <- #{device_mode}")
      File.write!("#{port_path}/mode", device_mode)
      :timer.sleep(500)

      if not Device.self_loading_on_brickpi?(device_type) do
        Logger.info("#{port_path}/set_device <- #{device_code}")
        :timer.sleep(500)
        File.write!("#{port_path}/set_device", device_code)
      end

      :ok
    else
      {:error, "Incompatible or incorrect #{port} and #{device_type}"}
    end
  end

  @doc "Get brickpi port number"
  def brickpi_port_number(port) do
    case port do
      :in1 -> 0
      :in2 -> 1
      :in3 -> 2
      :in4 -> 3
      :outA -> 4
      :outB -> 5
      :outC -> 6
      :outD -> 7
    end
  end
end
