defmodule Andy.SoundSpec do
  @moduledoc "Struct for sound player specifications"

  # properties name and props are required to be a *Spec
  # matching device has its props augmented by the spec's props
  defstruct name: nil, type: nil, props: %{volume: :normal, speed: :normal}

  @doc "Does a sound player match a spec?"
  def matches?(%Andy.SoundSpec{} = sound_spec, device) do
    device.class == :sound and device.type == "#{sound_spec.type}"
  end
end
