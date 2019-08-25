defmodule Andy.GM.Detector do
  @moduledoc "A detector as generator of prediction errors from reading sense values"

  alias Andy.GM.{PubSub, Prediction, PredictionError, Belief}
  import Andy.Utils, only: [listen_to_events: 2, now: 0, platform_dispatch: 2]
  require Logger

  # wait at least half a second to read a new value - TODO - use device TTL?
  @refractory_interval 500

  # A detector receives predictions from GMs.
  # A detector is named "<device_type>:<device_port>:<sense>
  # It can validate predictions with conjecture names that match its name
  # Conjecture names can contain a wild card ("*") for any or all of the components of the
  # detector's name. E.g. "color:*:ambient"
  # Upon receiving a prediction it can validate, the detector
  #    - reads a value if not in refractory period else uses the last read value
  #    - compares the detected value with the prediction (expectations = %{detected: value})
  #    - if the value contradicts the expectation in the prediction, reports a prediction error

  defmodule State do
    defstruct name: nil,
              device: nil,
              sense: nil,
              # %{about => read}
              previous_reads: %{}
  end

  defmodule Read do
    defstruct value: nil,
              timestamp: nil
  end

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([device, sense]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: {__MODULE__, :start_link, [device, sense]}
    }
  end

  @doc "Start a named detector on a sensing device"
  def start_link(device, sense) do
    name = name(device, sense)

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

  # expectations = %{detector_name: value}
  def handle_event(
        {:prediction,
         %Prediction{
           # "device_type:device_port:sense" where any can be wild-carded. Eg. "*:*:distance"
           conjecture_name: conjecture_name,
           about: about,
           expectations: %{detected: _expectation}
         } = prediction},
        state
      ) do
    if name_match?(conjecture_name, state) do
      {value, updated_state} = read_value(about, state)

      case maybe_prediction_error(prediction, value, conjecture_name, about, state) do
        nil ->
          :ok

        prediction_error ->
          PubSub.notify({:prediction_error, prediction_error})
      end

      updated_state
    else
      state
    end
  end

  # ignore event
  def handle_event(
        _event,
        state
      ) do
    state
  end

  ### PRIVATE

  defp name(device, sense) do
    "#{device.type}:#{device.port}:#{sense}"
  end

  defp name_match?(conjecture_name, %State{device: device, sense: sense}) do
    case String.split(conjecture_name, ":") do
      [device_type_s, device_port_s, sense_name_s] ->
        device_type = atomize_if_name(device_type_s)
        device_port = atomize_if_name(device_port_s)

        sense_name =
          case String.split(sense_name_s, "/") do
            [sense_name_s] ->
              atomize_if_name(sense_name_s)

            [sense_name_s, number_s] ->
              {number, _} = Integer.parse(number_s)
              {atomize_if_name(sense_name_s), number}
          end

        device_type in ["*", device.type] and device_port in ["*", device.port] and
          sense_name in ["*", sense]

      _other ->
        false
    end
  end

  defp atomize_if_name("*"), do: "*"
  defp atomize_if_name(name) when is_binary(name), do: String.to_atom(name)

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
  defp maybe_prediction_error(prediction, value, conjecture_name, about, %State{name: name}) do
    values = %{detected: value}
    size = Prediction.prediction_error_size(prediction, values)

    if size == 0.0 do
      nil
    else
      belief =
        Belief.new(
          source: name,
          conjecture_name: conjecture_name,
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
