defmodule Andy.SoundPlayer do
  @moduledoc "A Linux sound player"

  alias Andy.{Device, Speaker}
  require Logger

  def new() do
    %Device{mod: __MODULE__,
      class: :sound,
      path: "speech",
      port: nil,
      type: "speech",
      mock: true
    }
  end

  @doc "Execute a sound command"
  def execute_command(sound_player, command, params) do
    apply(__MODULE__, command, [sound_player | params])
    sound_player
  end

  @doc "The sound player says out loud the given words"
  def speak(_sound_player, words) do
    speak(words)
  end

  ###

  @doc "Speak out words with a given volume, speed and voice"
  def speak(words, volume, speed, v \\ nil) do
    Speaker.linux_speak(words, volume, speed, v)
  end

  @doc "Speak words loud and clear"
  def speak(words) do
    speak(words, 300, 160)
  end

end
