defmodule Andy.PG2Communicator do
	@moduledoc "Communicating with other smart things via pg2"

	@behaviour Andy.Communicating
	
	use GenServer
	alias Andy.{Percept, PubSub}
	alias Andy
	require Logger

	@name __MODULE__
	@ttl 10_000

	### API

	@doc "Star the communication server"
	def start_link(_) do
		Logger.info("Starting #{@name}")
		GenServer.start_link(@name, [], [name: @name])
	end

	@doc "Broadcast info to the community"
	def broadcast(_device, info) do
		GenServer.cast(@name, {:broadcast, info})
	end

	@doc "Report up to a member of the parent community"
	def send_percept(_device, _url, _about, _value) do
		Logger.warn("Sending percepts not implemented by #{@name}")
	end

	def senses_awakened_by(sense) do
		GenServer.call(@name, {:senses_awakened_by, sense})
	end

	def port() do
		Andy.community_name()
	end
	
	### CALLBACK

	def init([]) do
		group = Andy.community_name() # the pg2 group is the community's name
		{:ok, _pid} = :pg2.start()
		:ok = :pg2.create(group)
		:ok = :pg2.join(group, self())
		Logger.info("Joined community #{group}")
		{:ok, %{group: group, id_channels: [], community_name: group}}
	end

	def handle_cast({:broadcast, info},
									%{group: group,
										community_name: community_name} = state) do
		members = :pg2.get_members(group)
		Logger.info("COMMUNICATOR #{inspect Node.self()} broadcasting #{inspect info} to #{inspect Node.list()}")
		members
		|> Enum.each(&(send_to_peer(&1, info, community_name)))
		{:noreply, state}
	end

	def handle_cast({:communication, from_node, info, id_channel, community_name},
									%{id_channels: id_channels} = state) do 
		if from_node != Node.self() do
			Logger.info("COMMUNICATOR #{inspect Node.self()} heard #{inspect info} from #{inspect from_node} in community #{community_name} and with id channel #{id_channel}")
			percept = Percept.new(about: :heard,
														value: %{from: from_node, info: info, id_channel: id_channel, community: community_name})
			PubSub.notify_id_channel(id_channel, community_name) # not handled by anyone for now
			PubSub.notify_perceived(%{percept |
														 ttl: @ttl,
														 source: @name})
			{:noreply, %{state | id_channels: ([id_channel | id_channels] |> Enum.uniq())}}
		else
			{:noreply, state}
		end
	end

	def handle_call({:senses_awakened_by, sense}, _from, %{id_channels: id_channels} = state) do
		senses = case sense do
							 :heard ->
								 Enum.reduce(id_channels,
														 [],
									 fn(id_channel, acc) ->
										 acc ++ Andy.senses_for_id_channel(id_channel)
									 end)
							 _ ->
								 []
						 end
		{:reply, senses, state}
	end

	### PRIVATE
	
	defp send_to_peer(to_node, info, community_name) do
    id_channel = Andy.id_channel() # how to sense the sender
		GenServer.cast(to_node, {:communication, Node.self(), info, id_channel, community_name})
	end
	
end	
