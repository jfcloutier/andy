defmodule Andy.DetectorsSupervisor do
	@moduledoc "Supervisor of dynamically started detectors"

	@name __MODULE__
	use Supervisor
	alias Andy.Detector
	require Logger

	@doc "Start the detectors supervisor, linking it to its parent supervisor"
	def start_link() do
		Logger.info("Starting #{@name}")
		Supervisor.start_link(@name, [], [name: @name])
	end

	@doc "Start a supervised detector worker for a sensing device"
	def start_detector(sensing_device) do
#		Logger.debug("Starting Detector on #{sensing_device.path}") 
		{:ok, _pid} = Supervisor.start_child(@name, [sensing_device])
	end

	## Callbacks
	
	def init(_) do
		children = [worker(Detector, [], restart: :permanent)]
		supervise(children, strategy: :simple_one_for_one)
	end

end
