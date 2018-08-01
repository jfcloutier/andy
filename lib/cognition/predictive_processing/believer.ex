defmodule Andy.Believer do

  @moduledoc "Given a generative model, updates belief in it upon prediction errors."

  require Logger
  alias Andy.{ InternalCommunicator, Belief }

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([generative_model_conf]) do
    %{ # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [generative_model_conf] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(generative_model) do
    { :ok, pid } = Agent.start_link(
      fn () ->
        register_internal()
        %{
          model: generative_model,
          belief: Belief.new()
        }
      end,
      [name: generative_model.name]
    )
    Logger.info("#{__MODULE__} started on generative model #{generative_model.name}")
    { :ok, pid }
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    InternalCommunicator.register(__MODULE__)
  end

  def handle_event(
        { :prediction_error, %{ generative_model_name: model_name } = prediction_error },
        %{
          generative_model: %{
            name: name
          }
        } = state
      ) when model_name == name do
    process_prediction_error(prediction_error, state)
    state
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  # PRIVATE

  defp process_prediction_error(prediction_error, state) do
    # TODO
    state
  end

end