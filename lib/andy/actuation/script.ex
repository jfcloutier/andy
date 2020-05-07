defmodule Andy.Script do
  @moduledoc "Activation script"

  require Logger
  import Andy.Utils, only: [platform_dispatch: 2]
  alias Andy.AndyWorldGateway

  defstruct name: nil, steps: [], devices: nil

  @doc "Make a new script"
  def new(name, devices) do
    %Andy.Script{name: name, devices: devices}
  end

  @doc "Add a step to the script"
  def add_step(script, device_name, command) do
    add_step(script, device_name, command, [])
  end

  def add_step(script, device_name, command, params) do
    cond do
      device_name == :all or device_name in Map.keys(script.devices) ->
        %Andy.Script{
          script
          | steps: script.steps ++ [%{device_name: device_name, command: command, params: params}]
        }

      true ->
        throw("Unknown device #{device_name}")
    end
  end

  @doc "Add a timer wait to the script"
  def add_wait(script, msecs) do
    %Andy.Script{script | steps: script.steps ++ [%{sleep: msecs}]}
  end

  def add_wait(script, device_name, property, test) do
    cond do
      device_name == :all or device_name in Map.keys(script.devices) ->
        %Andy.Script{
          script
          | steps: script.steps ++ [%{wait_on: device_name, property: property, test: test}]
        }

      true ->
        throw("Unknown device #{device_name}")
    end
  end

  @doc "Execute the steps and waits of the script"
  def execute(actuator_type, script) do
    updated_devices =
      Enum.reduce(
        script.steps,
        script.devices,
        fn step, acc ->
          case step do
            %{device_name: device_name, command: command, params: params} ->
              execute_command(actuator_type, device_name, command, params, acc)

            %{sleep: msecs} ->
              sleep(msecs, acc)

            %{wait_on: device_name, property: property, test: test, timeout: timeout} ->
              wait_on(device_name, property, test, timeout, acc)
          end
        end
      )

    %Andy.Script{script | devices: updated_devices}
  end

  ### Private

  defp execute_command(actuator_type, device_name, command, params, all_devices) do
    devices =
      case device_name do
        :all -> Map.values(all_devices)
        name -> [Map.get(all_devices, name)]
      end

    updated_devices = Enum.reduce(
      devices,
      all_devices,
      fn device, acc ->
        module = platform_dispatch(:device_manager, [actuator_type])
        updated_device = apply(module, :execute_command, [device, command, params])

        Map.put(acc, device_name, updated_device)
      end
    )

    if Andy.simulation?(), do: AndyWorldGateway.actuate(actuator_type, command)
    updated_devices
  end

  defp sleep(msecs, all_devices) do
    Logger.info("SLEEPING for #{msecs}")
    :timer.sleep(msecs)
    all_devices
  end

  defp wait_on(_device_name, _property, _test, _timeout, all_devices) do
    # TODO
    all_devices
  end
end
