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

  def start_link(_) do
    {:ok, pid} =
      Agent.start_link(
        fn ->
          %{listening?: false, placed?: false}
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

  def handle_event({:actuated, intent}, %{placed?: placed?} = state) do
    name = Andy.name()
    Logger.info("Notifying Andy World that #{name} actuated")
    if placed? do
      :ok = GenServer.call(
        {:global, :andy_world},
        {:actuate, name, intent.kind})
    else
      Logger.warn("Failed to notify Andy World of actuation. #{name} is not placed.")
    end
    state
  end

  def handle_event({event_name}, state) do
    name = Andy.name()
    :ok = GenServer.cast(
        {:global, :andy_world},
        {:event, name, event_name})
    state
  end

  def handle_event({event_name, payload}, state) do
    name = Andy.name()
    :ok = GenServer.cast(
        {:global, :andy_world},
        {:event, name, {event_name, "#{inspect payload}"}})
    state
  end

  def place_robot() do
    name = Andy.name()
    Logger.info("Placing #{name} in Andy World")
    Agent.cast(
      @name,
      fn state ->
        %{row: row, column: column, orientation: orientation} = start_state(name)

        :ok =
          GenServer.call(
            {:global, :andy_world},
            {:place_robot,
             name: name,
             node: node(),
             row: row,
             column: column,
             orientation: orientation,
             sensor_data: sensor_data(),
             motor_data: motor_data()}
          )

        %{state | placed?: true}
      end
    )
  end

  def read_sense(device, sense) do
    name = Andy.name()
    Logger.info("Reading #{sense} of #{name} from Andy World")
    Agent.get(
      @name,
      fn %{placed?: placed?} = _state ->
        if placed? do
          {:ok, value} =
            GenServer.call(
              {:global, :andy_world},
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

  #### PRIVATE

  defp start_state(name) do
    start =
      Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:start) |> Map.fetch!(name)

    Logger.info("#{name} is starting with #{inspect(start)}")
    start
  end

  defp sensor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:sensor_state)
  end

  defp motor_data() do
    Application.fetch_env!(:andy, :mock_config) |> Keyword.fetch!(:motor_state)
  end
end
