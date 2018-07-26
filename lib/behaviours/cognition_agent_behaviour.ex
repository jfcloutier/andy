defmodule Andy.CognitionAgentBehaviour do

  @type state :: any()
  @type event :: any()

  @callback handle_event(event(), state()) :: state()
  # A reminder to register - TODO remove eventually
  @callback register_internal() :: :ok

end