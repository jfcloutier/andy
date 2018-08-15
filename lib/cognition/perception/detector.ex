defmodule Andy.Detector do
  @moduledoc "A detector polling a sensor or motor for senses it implements"

  require Logger
  alias Andy.{ Percept, PubSub, Device }
  import Andy.Utils, only: [platform_dispatch: 2, timeout: 0, default_ttl: 1]

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([device, sense]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [device, sense] }
    }
  end

  @doc "Start a detector on a sensing device, to be linked to its supervisor"
  def start_link(device, sense) do
    name = "#{Device.name(device)}:#{sense}"
    { :ok, pid } = Agent.start_link(
      fn () ->
        register_internal()
        %{
          detector_name: name,
          device: device,
          sense: sense,
          previous_values: %{ },
          polling_interval_secs: :infinity,
          polling_task: nil
        }
      end,
      [name: name]
    )
    Logger.info("#{__MODULE__} started on #{inspect device.type} device")
    { :ok, pid }
  end

  def detects?(
        detector_pid,
        %{ class: class, port: port, type: type, sense: sense }
      ) do
    Agent.get(
      detector_pid,
      fn (device: device, sense: sense_detected) ->
        (class == "*" or device.class == class)
        and (port == "*" or device.port == port)
        and (type == "*" or device.type == type)
        and (sense == "*" or sense_detected == sense)
      end
    )
  end

  def set_polling_priority(detector_pid, priority) do
    Agent.update(
      detector_pid,
      fn (%{
            detector_name: detector_name,
            device: device,
            sense: sense,
            polling_interval_secs: polling_interval_secs,
            polling_task: polling_task
          } = state) ->
        secs = polling_interval_from_priority(device, sense, priority)
        cond do
          secs == polling_interval_secs ->
            # Change nothing
            state
          secs == :infinity ->
            if polling_task != nil, do: Task.shutdown(polling_task)
            Logger.info("Stopped polling #{device.mod} about #{sense}")
            %{
              state |
              polling_task: nil,
              polling_interval_secs: :infinity
            }
          true ->
            if polling_task != nil, do: Task.shutdown(polling_task)
            Logger.info("Now polling #{device.mod} about #{sense} every #{secs} secs")
            %{
              state |
              polling_task: Task.async(fn -> detect(detector_name) end),
              polling_interval_secs: secs
            }
        end
      end
    )
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  def detect(detector_name) do
    polling_interval = Agent.get(
      detector_name,
      fn (%{ polling_interval_secs: interval } = _state) ->
        interval
      end
    )
    poll(detector_name)
    Process.sleep(polling_interval * 1000)
    detect(detector_name)
  end

  ### Private

  # TODO - Make device and sense-specific?
  defp polling_interval_from_priority(_device, _sense, priority) do
    base_ttl = default_ttl(:percept) # one fifth of persistence in memory
    case priority do
      :high -> min(500, round(base_ttl / 20))
      :medium -> min(2000, round(base_ttl / 5))
      :low -> min(5000, round(base_ttl / 2))
      :none -> :infinity
    end
  end

  defp poll(detector_name) do
    Agent.update(
      detector_name,
      fn (%{ device: device, sense: sense } = state) ->
        { value, updated_device } = read(device, sense)
        if value != nil do
          previous_value = Map.get(state.previous_values, sense, nil)
          nudged_value = platform_dispatch(:nudge, [updated_device, sense, value, previous_value])
          about = %{ class: device.class, port: device.port, type: device.type, sense: sense }
          percept = Percept.new(
            about: about,
            value: nudged_value
          )
          %Percept{
            percept |
            source: detector_name,
            ttl: default_ttl(:percept),
            resolution: sensitivity(updated_device, sense)
          }
          |> PubSub.notify_perceived()
          %{
            state |
            device: updated_device,
            previous_values: Map.put(state.previous_values, sense, percept.value)
          }
        else
          %{ state | device: updated_device }
        end
      end,
      timeout()
    )
    :ok
  end

  defp read(device, sense) do
    case device.class do
      :sensor -> platform_dispatch(:sensor_read_sense, [device, sense])
      :motor -> platform_dispatch(:motor_read_sense, [device, sense])
    end
  end

  defp sensitivity(device, sense) do
    case device.class do
      :sensor -> platform_dispatch(:sensor_sensitivity, [device, sense])
      :motor -> platform_dispatch(:motor_sensitivity, [device, sense])
    end
  end

end
