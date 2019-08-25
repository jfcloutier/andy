defmodule Andy.Lighting do
  alias Andy.Device

  @doc "Get left vs right position of the LED"
  @callback position(led :: %Device{}) :: atom

  @doc "Get the color of the LED"
  @callback color(led :: %Device{}) :: atom

  @doc "Get the LED max brightness"
  @callback max_brightness(led :: %Device{}) :: number

  @doc "Get the current brightness"
  @callback brightness(led :: %Device{}) :: number

  @doc "Set the brightness"
  @callback set_brightness(led :: %Device{}, value :: number) :: %Device{}
end
