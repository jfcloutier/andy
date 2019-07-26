defmodule Andy.Communicating do
  alias Andy.Device

  @doc "A name to give to the communicator device's  port"
  @callback port() :: binary

  @doc "Broadcast info to all other smart things in the community"
  @callback broadcast(device :: %Device{}, info :: any) :: any

  @doc "Send a percept (typically) to the member of another community"
  @callback send_percept(device :: %Device{}, url :: any, about :: any, value :: any) :: any

  @doc "The senses that become attended to when a given sense is also attended to"
  @callback senses_awakened_by(sense :: any) :: [any]
end
