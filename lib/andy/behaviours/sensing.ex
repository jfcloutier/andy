defmodule Andy.Sensing do
  alias Andy.Device

  @doc "Get all the senses a sensor possesses"
  @callback senses(sensor :: %Device{}) :: [any]

  @doc "Get the current value of a sense"
  @callback read(sensor :: %Device{}, sense :: any) :: any

  @doc "Get the sensitivity of the device; the change in value to be noticed"
  @callback sensitivity(sensor :: %Device{}, sense :: any) :: integer | nil
end
