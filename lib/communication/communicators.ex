defmodule Andy.Communicators do
	@moduledoc "Inter-smart thing communication"

	require Logger
	alias Andy.Device
	alias Andy.{PG2Communicator, RESTCommunicator}

	@doc "Get all available communicator"
  def communicators() do
		[:pg2, :rest]
		|> Enum.map(&(init_communicator("#{&1}", module_for(&1))))
	end

	@doc"Find a communicator device by type"
	def communicator(type: type) do
		communicators()
		|> Enum.find(&(type(&1) == type))
	end

	  @doc "Get the type of the communicator device"
  def type(communicator) do
    communicator.type
  end

  @doc "Execute a cound command"
  def execute_command(communicator, command, params) do
    apply(__MODULE__, command, [communicator | params])
    communicator
  end

	@doc "Broadcast information to all community members via a communicator device"
	def broadcast(communicator_device, info) do
		apply(communicator_device.mod, :broadcast, [communicator_device, info])
	end

	@doc "Send a percept to a member of a remote community via a communicator device"
	def send_percept(communicator_device, url, about, value ) do
		apply(communicator_device.mod, :send_percept, [communicator_device, url, about, value])
	end

	### Private

  defp init_communicator(type, communicator_module) do
    %Device{mod: communicator_module,
						class: :comm,
            path: "#{communicator_module}",
            port: apply(communicator_module, :port, []),
            type: type
           }
  end

	defp module_for(type) do
		case type do
			:pg2 -> PG2Communicator
			:rest -> RESTCommunicator
		  other ->
				error = "Unknown type #{other} of communicator"
				Logger.error(error)
				raise error
		end
	end
	
end
