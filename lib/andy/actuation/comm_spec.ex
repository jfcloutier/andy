defmodule Andy.CommSpec do
  @moduledoc "Struct for communicator specifications"

  import Andy.Utils

  # properties name and props are required to be a *Spec
  # matching device has its props augmented by the spec's props
  defstruct name: nil, type: nil, props: %{ttl: convert_to_msecs({30, :secs})}

  @doc "Does a communicator match a spec?"
  def matches?(%Andy.CommSpec{type: type}, device) do
    device.class == :comm and device.type == "#{type}"
  end
end
