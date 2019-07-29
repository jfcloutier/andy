defmodule Andy.GM.Detector do
  @moduledoc "A detector as generator of beliefs"

  alias Andy.Device
  import Andy.Utils, only: [listen_to_events: 2]
  require Logger

  # TODO - A detector receives predictions from GMs.
  # It detect a value if not in refractory period and there's at least one received prediction.
  # For each received prediction, it notifies of a prediction error if the detected value
  # is not the one predicted.  It then removes the prediction and enters refractory period.
  # A detector is its own conjecture (I assert that x is detected)

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([device, sense]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: {__MODULE__, :start_link, [device, sense]}
    }
  end

  @doc "Start a detector on a sensing device, to be linked to its supervisor"
  def start_link(device, sense) do
    name = String.to_atom("#{Device.name(device)}-#{inspect(sense)}")

    {:ok, pid} =
      Agent.start_link(
        fn ->
          %{
            detector_name: name,
            device: device,
            sense: sense,
            previous_values: %{},
            polling_interval_msecs: :infinity,
            polling_task: nil
          }
        end,
        name: name
      )

    listen_to_events(pid, __MODULE__)
    Logger.info("#{__MODULE__} started named #{name}")
    {:ok, pid}
  end

  ### Event handling

  def handle_event(_something, state) do
    # TODO - return new state
    state
  end

  # TODO
end
