defmodule Andy.SoundPlayer do
  @moduledoc "A Linux sound player"

  alias Andy.Device
  import Andy.Utils, only: [platform_dispatch: 1]
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
    spawn(fn -> apply(__MODULE__, command, [sound_player | params]) end)
    sound_player
  end

  @doc "The sound player says out loud the given words"
  def speak(_sound_player, words) do
    speak(words)
  end

  ###

  @doc "Speak out words with a given volume, speed and voice"
  def speak(words, volume, speed, v \\ nil) do
    voice = v || platform_dispatch(:voice)
    args =  ["-a", "#{volume}", "-s", "#{speed}", "-v", "#{voice}", words]
    spawn(fn() -> System.cmd("espeak", args) end)
  end

  @doc "Speak words loud and clear"
  def speak(words) do
    speak(words, 300, 160)
  end

end
