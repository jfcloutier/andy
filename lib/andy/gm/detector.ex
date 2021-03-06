defmodule Andy.GM.Detector do
  @moduledoc "A detector as generator of prediction errors from reading sense values"

  alias Andy.GM.{PubSub, Prediction, PredictionError, Belief}
  import Andy.Utils, only: [listen_to_events: 3, now: 0, platform_dispatch: 2]
  require Logger

  # TODO - Re-introduce nudging and sensitivity

  # wait at least half a second to read a new value
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
    Logger.info("Starting detector #{inspect(name)}")

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

    Logger.info("#{__MODULE__} started detector named #{name}")
    listen_to_events(pid, __MODULE__, name)
    {:ok, pid}
  end

  def detector_name?(name) do
    name_s = "#{name}"
    Enum.count(String.split(name_s, ":")) == 3
  end

  # e.g. :"infrared:MOCK:beacon_distance/1" matches pattern "*:*:beacon_distance/1"?
  def name_matches_pattern?(name, name_pattern) do
    name_s = "#{name}"
    [n_device, n_port, n_sense] = String.split(name_s, ":")
    [p_device, p_port, p_sense] = String.split(name_pattern, ":")

    p_device in [n_device, "*"] and
      p_port in [n_port, "*"] and
      p_sense in [n_sense, "*"]
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
      )
      when is_binary(conjecture_name) do
    if name_match?(conjecture_name, state) do
      Logger.info("#{inspect(detector_name(state))}: Received prediction #{inspect(prediction)}")
      {value, updated_state} = read_value(about, state)

      case maybe_prediction_error(prediction, value, conjecture_name, about, state) do
        nil ->
          :ok

        prediction_error ->
          PubSub.notify({:prediction_error, prediction_error})
      end

      updated_state
    else
      Logger.debug(
        "NO NAME MATCH for detector #{state.name} for conjecture #{conjecture_name} and device #{
          inspect(state.device)
        } and sense #{inspect(state.sense)}"
      )

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
    clean_port =
      case String.split(device.port || "MOCK", ":") do
        [port] ->
          port

        [_, port, _] ->
          port

        other ->
          [port | _] = Enum.reverse(other)
          port
      end

    "#{device.type}:#{clean_port}:#{sense}" |> String.to_atom()
  end

  defp detector_name(%State{name: name}) do
    name
  end

  defp name_match?(conjecture_name, %State{device: device, sense: sense}) do
    case String.split(conjecture_name, ":") do
      [device_type_s, device_port_s, sense_name_s] ->
        device_type = atomize_if_name(device_type_s)
        device_port = atomize_if_name(device_port_s)
        sense_name = atomize_if_name(sense_name_s)

        device_type in ["*", device.type] and device_port in ["*", device.port] and
          sense_name in ["*", sense]

      _other ->
        false
    end
  end

  defp atomize_if_name("*"), do: "*"
  defp atomize_if_name(name) when is_binary(name), do: String.to_atom(name)

  # If value read is :unknown, use previous reading if any.
  # If two :unknown reads in a row, the second one will be returned as :unknown
  defp read_value(
         about,
         %State{device: device, sense: sense, previous_reads: previous_reads} = state
       ) do
    time_now = now()

    {effective_reading, updated_state} =
      case recent_read(previous_reads, about, time_now) do
        nil ->
          Logger.info("#{inspect(detector_name(state))}: Reading new value")
          {reading, updated_device} = value = read(device, sense)
          previous_read = Map.get(previous_reads, about)

          if reading == :unknown and previous_read != nil do
            Logger.info(
              "#{inspect(detector_name(state))}: Value is :unknown, using previous read #{
                inspect(previous_read)
              }"
            )

            {previous_reading, _updated_device} = previous_read.value
            # Return previous reading but store the :unknown one as previous read
            {previous_reading,
             %State{
               state
               | device: updated_device,
                 previous_reads:
                   Map.put(previous_reads, about, %Read{value: value, timestamp: time_now})
             }}
          else
            # return :unknown reading and make it the previous read
            read = %Read{value: value, timestamp: time_now}

            {reading,
             %State{
               state
               | device: updated_device,
                 previous_reads: Map.put(previous_reads, about, read)
             }}
          end

        # Prior read not yet expired
        prior_read ->
          {prior_reading, _prior_device} = prior_read.value
          # No change of state
          {prior_reading, state}
      end

    Logger.info("#{inspect(detector_name(state))}: Read #{inspect(effective_reading)}")
    {effective_reading, updated_state}
  end

  # Unexpired previous read else nil
  defp recent_read(previous_reads, about, time_now) do
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

  # Prediction error of size >= 0 (size == 0 means a prediction non-error - needed by GM to check if all activated detectors reported in)
  defp maybe_prediction_error(
         %Prediction{goal: goal_or_nil} = prediction,
         value,
         conjecture_name,
         about,
         %State{name: name} = state
       ) do
    Logger.info(
      "#{inspect(detector_name(state))}: May be prediction error on #{inspect(prediction)}"
    )

    values = %{detected: value}
    size = Prediction.prediction_error_size(prediction, values)

    belief =
      Belief.new(
        source: name,
        conjecture_name: conjecture_name,
        about: about,
        goal: goal_or_nil,
        values: values
      )

    prediction_error = %PredictionError{
      prediction: prediction,
      size: size,
      belief: belief
    }

    if size > 0,
      do:
        Logger.info(
          "#{inspect(detector_name(state))}: Prediction error #{inspect(prediction_error)}"
        )

    prediction_error
  end

  # Read a sense from a sensor device
  defp read(device, sense) do
    case device.class do
      :sensor -> platform_dispatch(:sensor_read_sense, [device, sense])
      :motor -> platform_dispatch(:motor_read_sense, [device, sense])
    end
  end
end
