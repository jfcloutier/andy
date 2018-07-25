defmodule Andy.Detector do
  @moduledoc "A detector polling a sensor or motor for senses it implements"

  require Logger
  alias Andy.{ Percept, InternalCommunicator, Device }
  import Andy.Utils, only: [platform_dispatch: 2, timeout: 0, default_ttl: 1]

  @behaviour Andy.CognitionAgentBehaviour


  def poll(name, sense) do
    Agent.get_and_update(
      name,
      fn (state) ->
        { value, updated_device } = read(state.device, sense)
        if value != nil do
          previous_value = Map.get(state.previous_values, sense, nil)
          nudged_value = platform_dispatch(:nudge, [updated_device, sense, value, previous_value])
          percept = Percept.new(about: sense, value: nudged_value)
          %Percept{
            percept |
            source: name,
            ttl: default_ttl(:percept),
            resolution: sensitivity(updated_device, sense)
          }
          |> InternalCommunicator.notify_perceived()
          {
            :ok,
            %{
              state |
              device: updated_device,
              previous_values: Map.put(state.previous_values, sense, percept.value)
            }
          }
        else
          { :ok, %{ state | device: updated_device } }
        end
      end,
      timeout()
    )
    :ok
  end

  ### Cognition Agent Behaviour

  @doc "Start a detector on a sensing device, to be linked to its supervisor"
  def start_link(device) do
    name = Device.name(device)
    { :ok, pid } = Agent.start_link(
      fn () ->
        %{ device: device, previous_values: %{ } }
      end,
      [name: name]
    )
    Logger.info("#{__MODULE__} started on #{inspect device.type} device")
    { :ok, pid }
  end

  def handle_event({:poll, sensing_device, sense}, state) do
    poll(Device.name(sensing_device), sense)
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### Private

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
