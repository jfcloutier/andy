defmodule Andy.GM.Detector do
  @moduledoc "A detector as generator of prediction errors"

  alias Andy.GM.{PubSub, Prediction, PredictionError, Belief}
  import Andy.Utils, only: [listen_to_events: 2, now: 0, platform_dispatch: 2]
  require Logger

  # half a second
  @refractory_interval 500

  # A detector receives predictions from GMs.
  # Upon receiving a prediction it can validate, the detector
  #    - reads a value if not in refractory period else uses the last read value
  #    - compares the detected value with the prediction
  #    - if the value contradicts the prediction, reports a prediction error
  # A detector named X is its own conjecture; its asserts that X for object Y is detected

  defmodule State do
    defstruct name: nil,
              device: nil,
              sense: nil,
              previous_reads: %{}
  end

  defmodule Read do
    defstruct value: nil,
              timestamp: nil
  end

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([name, device, sense]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: {__MODULE__, :start_link, [name, device, sense]}
    }
  end

  @doc "Start a named detector on a sensing device"
  def start_link(name, device, sense) do
    {:ok, pid} =
      Agent.start_link(
        fn ->
          %State{
            name: name,
            device: device,
            sense: sense
          }
        end,
        name: name
      )

    listen_to_events(pid, __MODULE__)
    Logger.info("#{__MODULE__} started detector named #{name}")
    {:ok, pid}
  end

  ### Event handling

  # value_distributions = %{detector_name: value_distribution}
  def handle_event(
        {:prediction,
         %Prediction{
           conjecture_name: name,
           about: about,
           value_distributions: %{detected: _value_distribution}
         } = prediction},
        %State{name: name} = state
      ) do
    {value, updated_state} = read_value(about, state)

    case maybe_prediction_error(prediction, value, name, about) do
      nil ->
        :ok

      prediction_error ->
        PubSub.notify({:prediction_error, prediction_error})
    end

    updated_state
  end

  # ignore event
  def handle_event(
        _event,
        state
      ) do
    state
  end

  ### PRIVATE

  defp read_value(
         about,
         %State{device: device, sense: sense, previous_reads: previous_reads} = state
       ) do
    time_now = now()

    read =
      case previous_read(previous_reads, about, time_now) do
        nil ->
          value = read(device, sense)
          %Read{value: value, timestamp: time_now}

        prior_read ->
          prior_read
      end

    {read.value, %State{state | previous_reads: Map.put(previous_reads, about, read)}}
  end

  # Unexpired previous rea,d else nil
  def previous_read(previous_reads, about, time_now) do
    case Map.get(previous_reads, about) do
      nil ->
        nil

      %Read{timestamp: timestamp} = read ->
        if timestamp + @refractory_interval > time_now do
          read
        else
          nil
        end
    end
  end

  # Prediction error or nil
  defp maybe_prediction_error(prediction, value, name, about) do
    values = %{detected: value}
    size = Prediction.prediction_error_size(prediction, values)

    if size == 0.0 do
      nil
    else
      belief =
        Belief.new(
          source: name,
          conjecture_name: name,
          about: about,
          values: values
        )

      %PredictionError{
        prediction: prediction,
        size: size,
        belief: belief
      }
    end
  end

  # Read a sense from a sensor device
  defp read(device, sense) do
    case device.class do
      :sensor -> platform_dispatch(:sensor_read_sense, [device, sense])
      :motor -> platform_dispatch(:motor_read_sense, [device, sense])
    end
  end
end
