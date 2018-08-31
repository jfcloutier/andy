defmodule Andy.Device do
  @moduledoc "Data specifying a motor, sensor or LED."

  @doc """
  mod - Module that implements the device
  class - :sensor, :motor, :led, :sound etc.
  path - sys file where to read/write to interact with device
  port - the name of the port the device is connected to
  type - the type of motor, sensor or led
  props - idiosyncratic properties of the device
  mock - whether this is a mock device or a real one
  """
  alias __MODULE__

  defstruct mod: nil, class: nil, path: nil, port: nil, type: nil, props: %{ }, mock: false

  def mode(%Device{ mod: mod, type: type }) do
    apply(mod, :mode, [type])
  end

  def device_code(%Device{ mod: mod, type: type }) do
    apply(mod, :device_code, [type])
  end

  def senses(%Device{ mod: mod } = device) do
    apply(mod, :senses, [device])
  end

  def name(%Device{ path: path }) do
    String.to_atom(path)
  end

  def self_loading_on_brickpi?(device_type) do
    device_type in [:touch, :large, :medium]
  end

end