defmodule Andy.Attention do
  @moduledoc "Responsible for polling detectors as needed by predictors"

  require Logger
  alias Andy.{ PubSub }

  @name __MODULE__

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        register_internal()
        %{
          # [%{predictor_id: ..., detector_specs: ..., precision: ...}, ...] - precision in [:low, :medium, :high]
          attended_list: []
        }
      end,
      [name: @name]
    )
  end


  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  ## Handle timer events

  def handle_event({:attention_on, detector_specs, predictor_pid, precision}, state) do
    pay_attention(detector_specs, predictor_pid, precision)
  end

  def handle_event({:attention_off, predictor_pid}, state) do
    lose_attention(predictor_pid)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  defp pay_attention(detector_specs, predictor_pid, precision) do
    Agent.update(
      @name,
      fn (%{ attended_list: attended_list } = state) ->
        attended_minus = Enum.reduce(
          attended_list,
          [],
          fn (attended, acc) ->
            if attended.predictor_id == predictor_id and Percept.about_match?(
              detector_specs,
              attended.detector_specs
               ) do
              acc
            else
              [attended | acc]
            end
          end
        )
        new_attended = %{ predictor_id: predictor_id, detector_specs: detector_specs, precision: precision }
        %{ state | attended_list: [new_attended | attended_minus] }
      end
    )
    set_polling_precision(detector_specs)
  end

  defp lose_attention(predictor_pid) do
    detector_specs = Agent.get(
      @name,
      fn (%{ attended_list: attended_list }) ->
        case Enum.find(attended_list, &(&1.predictor_pid == predictor_pid)) do
          nil ->
            nil
          %{ detector_specs: specs } ->
            specs
        end
      end
    )
    Agent.update(
      @name,
      fn (%{ attended_list: attended_list } = state) ->
        attended_minus = Enum.reduce(
          attended_list,
          [],
          fn (attended, acc) ->
            if attended.predictor_id == predictor_id do
              acc
            else
              [attended | acc]
            end
          end
        )
        %{ state | attended_list: attended_minus }
      end
    )
    set_polling_precision(detector_specs)
  end

  defp set_polling_precision(nil) do
    :ok
  end

  defp set_polling_precision(detector_specs) do
    max_precision = Agent.get(
      @name,
      fn (%{ attended_list: attended_list }) ->
        Enum.reduce(
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
      end
    )
    DetectorsSupervisor.set_polling_precision(detector_specs, max_precision)
  end

end