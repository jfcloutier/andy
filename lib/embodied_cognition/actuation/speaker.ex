defmodule Andy.Speaker do
  @moduledoc "Agent that says one thing at a time"

  import Andy.Utils, only: [platform_dispatch: 1]
  require Logger
  use Agent

  @name __MODULE__

  def start_link(_) do
    { :ok, pid } = Agent.start_link(
      fn () ->
        %{ }
      end,
      [name: @name]
    )
    Logger.info("#{@name} started")
    { :ok, pid }
  end


  @doc "Speak out words with a given volume, speed and voice"
  def linux_speak(words, volume, speed, v) do
    Agent.cast(
      @name,
      fn (state) ->
        voice = v || platform_dispatch(:voice)
        args = ["-a", "#{volume}", "-s", "#{speed}", "-v", "#{voice}", words, "2>/dev/null"]
        System.cmd("espeak", args)
        state
      end
    )
  end

  @doc "Say words with a given volume, speed and voice"
  def ev3_speak(words, volume, speed, voice) do
    Agent.cast(
      @name,
      fn (state) ->
        :os.cmd('espeak -a #{volume} -s #{speed} -v #{voice} "#{words}"')
        state
      end
    )
  end

end