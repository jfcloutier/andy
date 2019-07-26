defmodule Andy.EmbodiedCognitionAgent do
  @type state :: any()
  @type event :: any()

  @callback handle_event(event(), state()) :: state()
end
