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
          # [%{predictor_id: ..., detector_specs: ..., priority: ...}, ...] - priority in [:low, :medium, :high]
          attended_list: []
        }
      end,
      [name: @name]
    )
  end

  #
  def pay_attention(detector_specs, predictor_pid, priority \\ :low) do
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
        new_attended = %{ predictor_id: predictor_id, detector_specs: detector_specs, priority: priority }
        %{ state | attended_list: [new_attended | attended_minus] }
      end
    )
    set_polling_priority(detector_specs)
  end

  defp set_polling_priority(detector_specs) do
    max_priority = Agent.get(
      @name,
      fn (%{ attended_list: attended_list }) ->
        Enum.reduce(
          attended_list,
          :none,
          fn (%{ detector_specs: specs, priority: priority }, acc) ->
            if Percept.about_match?(detector_specs, specs) do
              Andy.highest_priority(acc, priority)
            else
              acc
            end
          end
        )
      end
    )
    DetectorsSupervisor.set_polling_priority(detector_specs, max_priority)
  end

  def lose_attention(predictor_pid) do
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
    set_polling_priority(detector_specs)
  end


  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  ## Handle timer events

  def handle_event({ :prediction_error, prediction_error }, state) do
    # TODO
    # Choose and initiate a fulfillment to correct the prediction error
    # If fulfillment is via making a model true,
    # adjust effective priorities of predictors of other models of lesser priority
    state
  end

  def handle_event({ :prediction_fulfilled, prediction_fulfilled }, state) do
    # TODO
    # If fulfillment was by making a model true, then adjust effective priorities of predictors
    state
  end


  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

end