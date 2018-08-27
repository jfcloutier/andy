defmodule Andy.Ev3.BrickPi do

  require Logger
  alias Andy.Device
  alias Andy.Ev3.{ LegoSensor, LegoMotor }

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
    Logger.add_backend { LoggerFileBackend, :error }
    Logger.configure_backend { LoggerFileBackend, :error },
                             path: "andy.log",
                             level: :info
    #    Logger.remove_backend :console

    # Turn off kernel logging to the console
    #System.cmd("dmesg", ["-n", "1"])
  end

  defp initialize_brickpi_ports() do
    Enum.each(
      Andy.ports_config(),
      fn (%{ port: port_name, device: device_type }) ->
        set_brickpi_port(port_name, device_type)
      end
    )
  end

  @doc "Associate a BrickPi port with an Ev3 motor or sensor"
  def set_brickpi_port(port, device_type) do
    if (port in [:in1, :in2, :in3, :in4] and LegoSensor.sensor?(device_type))
       or (port in [:outA, :outB, :outC, :outD] and LegoMotor.motor?(device_type)) do
      port_path = "#{@ports_path}/port#{brickpi_port_number(port)}"
      Logger.info("#{port_path}/mode <- #{Device.mode(device_type)}")
      File.write!("#{port_path}/mode", Device.mode(device_type))
      :timer.sleep(500)
      if not Device.self_loading_on_brickpi?(device_type) do
        Logger.info("#{port_path}/set_device <- #{Device.device_code(device_type)}")
        :timer.sleep(500)
        File.write!("#{port_path}/set_device", Device.device_code(device_type))
      end
      :ok
    else
      { :error, "Incompatible or incorrect #{port} and #{device_type}" }
    end
  end

  @doc "Get brickpi port number"
  def brickpi_port_number(port) do
    case port do
      :in1 -> 0
      :in2 -> 1
      :outA -> 2
      :outB -> 3
      :in3 -> 4
      :in4 -> 5
      :outC -> 6
      :outD -> 7
    end
  end

end
