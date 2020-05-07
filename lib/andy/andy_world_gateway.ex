defmodule Andy.AndyWorldGateway do
  @moduledoc """
  The gateway to Andy World when in simulation mode.
  """
  import Andy.Utils, only: [listen_to_events: 3]
  require Logger
  @name __MODULE__

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link() do
    {:ok, pid} =
      Agent.start_link(
        fn ->
          playground_node = Andy.playground_node()
          Logger.info("Trying to connect to  node #{playground_node}")
          true = Node.connect(playground_node)
          place_robot()
          %{listening?: false, placed?: true}
        end,
        name: @name
      )

    listen_to_events(pid, __MODULE__, @name)
    Logger.info("#{@name} started")
    {:ok, pid}
  end

  def handle_event(
        {:listening, __MODULE__, name},
        state
      ) do
    if @name == name do
      Logger.info("#{name} is listening to events")
      %{state | listening?: true}
    else
      state
    end
  end

  def handle_event({event_name}, state) do
    name = Andy.name()

    :ok =
      GenServer.cast(
        playground(),
        {:event, name, event_name}
      )

    state
  end

  def handle_event({event_name, payload}, state) do
    name = Andy.name()

    :ok =
      GenServer.cast(
        playground(),
        {:event, name, {event_name, "#{inspect(payload)}"}}
      )

    state
  end

  def handle_event(_event, state), do: state

  def read_sense(device, sense) do
    name = Andy.name()

    Logger.warn(
      "Reading #{inspect(sense)} of device at #{device.port} #{inspect(name)} from Andy World"
    )

    Agent.get(
      @name,
      fn %{placed?: placed?} = _state ->
        if placed? do
          {:ok, value} =
            GenServer.call(
              playground(),
              {:read, name, device.port, sense}
            )

          {value, device}
        else
          Logger.warn("#{name} not placed yet. Can't read sense.")
          {nil, device}
        end
      end
    )
  end

  def set_motor_control(motor_port, control, value) do
    name = Andy.name()

    Logger.warn(
      "Setting motor control #{inspect(control)}, to #{inspect(value)} for #{inspect(motor_port)} of #{
        inspect(name)
      }"
    )

    Agent.get(
      @name,
      fn %{placed?: placed?} = _state ->
        if placed? do
          GenServer.call(
            playground(),
            {:set_motor_control, name, motor_port, control, value}
          )
        else
          Logger.warn("#{name} not placed yet. Can't set motor control.")
          :ok
        end
      end
    )
  end

  def actuate(actuator_type, command) do
    name = Andy.name()

    Logger.warn("Actuating #{inspect(actuator_type)} of #{inspect(name)}")

    Agent.get(
      @name,
      fn %{placed?: placed?} = _state ->
        if placed? do
          GenServer.call(
            playground(),
            {:actuate, name, actuator_type, command}
          )
        else
          Logger.warn("#{name} not placed yet. Can't actuate #{inspect actuator_type}.")
          :ok
        end
      end
    )
  end

  #### PRIVATE

  defp place_robot() do
    name = Andy.name()
    Logger.info("Placing #{name} in Andy World")
    %{row: row, column: column, orientation: orientation} = start_state(name)

    :ok =
      GenServer.call(
        playground(),
        {:place_robot,
         name: name,
         node: node(),
         row: row,
         column: column,
         orientation: orientation,
         sensor_data: sensor_data(),
         motor_data: motor_data()}
      )
  end

  defp playground() do
    {:playground, Andy.playground_node()}
  end

  defp start_state(name) do
    start =
      Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:start) |> Map.fetch!(name)

    Logger.info("#{name} is starting with #{inspect(start)}")
    start
  end

  defp sensor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:sensor_data)
  end

  defp motor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:motor_data)
  end
end
