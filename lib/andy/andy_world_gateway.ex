defmodule Andy.AndyWorldGateway do
  @moduledoc """
  The gateway to Andy World when in simulation mode.
  """
  import Andy.Utils, only: [listen_to_events: 3, get_andy_env: 2]
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

  def handle_event({gm_event_name, %{gm_name: gm_name, list: list}}, state) do
    name = Andy.name()

    payload =
      Enum.map(
        list,
        &%{label: inspect(&1), type: Andy.gm_element_type(&1), value: Map.from_struct(&1)}
      )

    :ok =
      GenServer.cast(
        playground(),
        {:event, name, {gm_event_name, %{gm_name: gm_name, list: payload}}}
      )

    state
  end

  def handle_event({event_name, payload}, state)
      when event_name in [:prediction, :prediction_error, :belief, :disbelief, :course_of_action] do
    name = Andy.name()
    label = inspect(payload)
    value = Map.from_struct(payload)

    :ok =
      GenServer.cast(
        playground(),
        {:event, name, {event_name, %{value: value, label: label}}}
      )

    state
  end

  def handle_event({event_name, raw_payload}, state) do
    name = Andy.name()
    payload = if is_struct(raw_payload), do: Map.from_struct(raw_payload), else: raw_payload

    :ok =
      GenServer.cast(
        playground(),
        {:event, name, {event_name, payload}}
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

  def actuate(actuator_type, command, params) do
    name = Andy.name()

    Logger.warn(
      "Actuating #{inspect(actuator_type)} of #{inspect(name)} with #{inspect(command)} (params were #{
        inspect(params)
      })"
    )

    Agent.get(
      @name,
      fn %{placed?: placed?} = _state ->
        if placed? do
          GenServer.call(
            playground(),
            {:actuate, name, actuator_type, command, params}
          )
        else
          Logger.warn("#{name} not placed yet. Can't actuate #{inspect(actuator_type)}.")
          :ok
        end
      end
    )
  end

  def place_robot() do
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

  #### PRIVATE

  defp playground() do
    {:playground, Andy.playground_node()}
  end

  # returns %{row: row, column: column, orientation: orientation}
  defp start_state(name) do
    [row_s, column_s, orientation_s] = get_andy_env("ANDY_PLACE", "0,0,0") |> String.split(",")
    {row, _} = Integer.parse(row_s)
    {column, _} = Integer.parse(column_s)
    {orientation, _} = Integer.parse(orientation_s)
    start = %{row: row, column: column, orientation: orientation}
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
