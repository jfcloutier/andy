defmodule Andy.MockRover.Tachomotor do
  @moduledoc "A mock large tachomotor"

  @behaviour Andy.Sensing
  @behaviour Andy.Moving

  alias Andy.{Device, AndyWorldGateway}
  require Logger

  def new(type, port_name) do
    %Device{
      mod: __MODULE__,
      class: :motor,
      path: "/mock/#{type}_motor/#{port_name}",
      type: type,
      mock: true,
      port: port_name
    }
  end

  # Sensing

  def senses(_) do
    [:speed, :position, :duty_cycle, :run_status]
  end

  def read(motor, sense) do
    # Not yet supported in AndyWorld
    case sense do
      :speed -> current_speed(motor)
      :position -> current_position(motor)
      :duty_cycle -> current_duty_cycle(motor)
      :run_status -> current_run_status(motor)
    end
  end

  def sensitivity(_motor, _sense) do
    nil
  end

  # Moving

  def reset(motor) do
    Logger.info("Resetting #{motor.path}")
    motor
  end

  def set_speed(motor, mode, speed) do
    Logger.info("Setting the speed of #{motor.path} to #{speed} #{mode}")

    set_motor_control(motor, :speed_mode, mode)
    |> set_motor_control(:speed, speed)
  end

  def reverse_polarity_control(motor) do
    Logger.info("Reversing polarity of #{motor.path}")
    reverse_polarity = reverse_polarity(motor)
    set_motor_control(motor, :polarity, reverse_polarity)
  end

  def set_duty_cycle(motor, duty_cycle) do
    Logger.info("Setting the duty cycle of #{motor.path} to #{duty_cycle}")
    set_motor_control(motor, :duty_cycle, duty_cycle)
  end

  def set_ramp_up(motor, msecs) do
    Logger.info("Setting ramp-up of #{motor.path} to #{msecs} msecs")
    set_motor_control(motor, :ramp_up, msecs)
  end

  def set_ramp_down(motor, msecs) do
    Logger.info("Setting ramp-down of #{motor.path} to #{msecs} msecs")
    set_motor_control(motor, :ramp_down, msecs)
  end

  # Not yet supported by AndyWorld
  def run(motor) do
    Logger.info("Running #{motor.path}")
    motor
  end

  # Not yet supported by AndyWorld
  def run_to_absolute(motor, degrees) do
    Logger.info("Running #{motor.path} to #{degrees} absolute degrees")
    motor
  end

  # Not yet supported by AndyWorld
  def run_to_relative(motor, degrees) do
    Logger.info("Running #{motor.path} to #{degrees} relative degrees")
    motor
  end

  def run_for(motor, msecs) when is_integer(msecs) do
    Logger.info("Running #{motor.path} for #{msecs} msecs")
    set_motor_control(motor, :time, msecs / 1000)
  end

  # Not yet supported by AndyWorld
  def coast(motor) do
    Logger.info("Coasting #{motor.path}")
    motor
  end

  # Not yet supported by AndyWorld
  def brake(motor) do
    Logger.info("Braking #{motor.path}")
    motor
  end

  # Not yet supported by AndyWorld
  def hold(motor) do
    Logger.info("Holding #{motor.path}")
    motor
  end

  # TODO - duplicated from Tachymotor
  def reverse_polarity(motor) do
    case get_control(motor, :polarity) do
      :normal -> set_control(motor, :polarity, :inversed)
      :inversed -> set_control(motor, :polarity, :normal)
    end
  end

  ### PRIVATE

  defp set_motor_control(motor, control, value) do
    :ok = AndyWorldGateway.set_motor_control(motor.port, control, value)
    set_control(motor, control, value)
  end

  defp set_control(motor, control, value) do
    controls = Map.get(motor.props, :controls, %{})
    updated_props = Map.put(motor.props, :controls, Map.put(controls, control, value))
    %Device{motor | props: updated_props}
  end

  defp get_control(motor, control) do
    Map.get(motor.props, :controls, %{}) |> Map.get(control)
  end

  defp current_speed(motor) do
    # delta speed
    value = 2 - :rand.uniform() * :rand.uniform(4)
    {value, motor}
  end

  defp current_position(motor) do
    value = :rand.uniform(20) - 10
    {value, motor}
  end

  defp current_duty_cycle(motor) do
    value = :rand.uniform(30)
    {value, motor}
  end

  defp current_run_status(motor) do
    value =
      case :rand.uniform(10) do
        0 -> :stopped
        1 -> :stalled
        2 -> :holding
        _ -> :running
      end

    {value, motor}
  end
end
