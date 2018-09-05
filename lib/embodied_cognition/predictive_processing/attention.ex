defmodule Andy.Attention do
  @moduledoc """
  Responsible for activating and deactivating detectors as needed by validators,
  and setting their polling frequency"
  """
  require Logger
  alias Andy.{ DetectorsSupervisor, Percept }
  import Andy.Utils, only: [listen_to_events: 2]

  @name __MODULE__

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the attention agent"
  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          # [%{validator_name: ..., detector_specs: ..., precision: ...}, ...] - precision in [:none, :low, :medium, :high]
          attended_list: []
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end


  ### Cognition Agent Behaviour

  ## Handle timer events

  def handle_event({ :attention_on, detector_specs, validator_name, precision }, state) do
    pay_attention(detector_specs, validator_name, precision, state)
  end

  def handle_event({ :attention_off, validator_name }, state) do
    lose_attention(validator_name, state)
  end

  def handle_event(_event, state) do
    # Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # Add, on behalf of a validator, to the detections that are active
  # and adjust the polling frequency of activated detectors.
  defp pay_attention(
         detector_specs,
         validator_name,
         precision,
         %{ attended_list: attended_list } = state
       ) do
    Logger.info("Paying attention to #{inspect detector_specs} for validator #{validator_name}")
    attended_minus = remove_attended(attended_list, detector_specs, validator_name)
    new_attended = %{ validator_name: validator_name, detector_specs: detector_specs, precision: precision }
    new_state = %{ state | attended_list: [new_attended | attended_minus] }
    adjust_polling_precision(detector_specs, new_state)
    new_state
  end

  # Remove, on behalf of a validator, from the detections that are active
  # and adjust the polling frequency of activated detectors.
  defp lose_attention(validator_name, %{ attended_list: attended_list } = state) do
    Logger.info("Losing attention for validator #{validator_name}")
    detector_specs = validator_detector_specs(validator_name, state)
    attended_minus = remove_any_attended(attended_list, validator_name)
    new_state = %{ state | attended_list: attended_minus }
    adjust_polling_precision(detector_specs, new_state)
    new_state
  end

  # Remove the given detector specs from what's attended to on behalf of a validator
  defp remove_attended(attended_list, detector_specs, validator_name) do
    Enum.reduce(
      attended_list,
      [],
      fn (attended, acc) ->
        if attended.validator_name == validator_name and Percept.about_match?(
          detector_specs,
          attended.detector_specs
           ) do
          acc
        else
          [attended | acc]
        end
      end
    )
  end

  # Remove all detector specs from what's attended to on behalf of a validator
  defp remove_any_attended(attended_list, validator_name) do
    Enum.reduce(
      attended_list,
      [],
      fn (attended, acc) ->
        if attended.validator_name == validator_name do
          acc
        else
          [attended | acc]
        end
      end
    )
  end

  # Get all detected specs being attended to for a validator
  defp validator_detector_specs(
         validator_name,
         %{ attended_list: attended_list } = _state
       ) do
    case Enum.find(attended_list, &(&1.validator_name == validator_name)) do
      nil ->
        nil
      %{ detector_specs: specs } ->
        specs
    end
  end

  defp adjust_polling_precision(nil, _state) do
    :ok
  end

  # Adjust the polling precision of attended to detectors
  defp adjust_polling_precision(detector_specs, %{ attended_list: attended_list } = _state) do
    max_precision = Enum.reduce(
      attended_list,
      :none,
      fn (%{ detector_specs: specs, precision: precision }, acc) ->
        if Percept.about_match?(detector_specs, specs) do
          Andy.highest_level(acc, precision)
        else
          acc
        end
      end
    )
    DetectorsSupervisor.set_polling_priority(detector_specs, max_precision)
  end

end