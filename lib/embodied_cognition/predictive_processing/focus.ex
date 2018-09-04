defmodule Andy.Focus do
  @moduledoc """
  Responsible for modulating the effective precisions of model predictors
  based on the relative priorities of the models with beliefs in need of being changed.
  """

  require Logger
  alias Andy.{ PubSub, GenerativeModels, Deprioritization }
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

  @doc "Start the agent"
  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          # [%Deprioritization{}]
          deprioritizations: []
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  ### Cognition Agent Behaviour

  def handle_event(
        { :believed_as_predicted, model_name, prediction_name, false },
        state
      ) do
    focus_on(model_name, prediction_name, state)
  end

  def handle_event(
        { :believed_as_predicted, model_name, prediction_name, true },
        state
      ) do
    focus_off(model_name, prediction_name, state)
  end

  def handle_event(
        { :believer_terminated, model_name },
        state
      ) do
    focus_off_unconditionally(model_name, state)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # Focus on a model, by reducing the effective precisions the predictors of competing models
  # (i.e. altering precision weighing), on behalf of a prediction that needs to be fulfilled about that model
  defp focus_on(model_name, prediction_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info("Focus: Focusing on model #{model_name} because belief prediction #{prediction_name} was invalidated")
    model = GenerativeModels.fetch!(model_name)
    competing_model_names = GenerativeModels.competing_model_names(model)
    updated_deprioritizations = Enum.reduce(
      competing_model_names,
      deprioritizations,
      fn (competing_model_name, acc) ->
        deprioritize(competing_model_name, model, prediction_name, acc)
      end
    )
    %{ state | deprioritizations: updated_deprioritizations }
  end

  defp deprioritize(competing_model_name, model, prediction_name, deprioritizations) do
    case find_deprioritization(deprioritizations, model.name, competing_model_name) do
      # Model already deprioritized competing model
      %Deprioritization{ prediction_names: prediction_names } = deprioritization ->
        Logger.info("Focus: Model #{competing_model_name} already deprioritized by #{model.name}")
        update_deprioritizations(
          deprioritizations,
          %Deprioritization{
            deprioritization |
            prediction_names: (
              [prediction_name | prediction_names]
              |> Enum.uniq())
          }
        )
      # New deprioritization of competing model by model, if it deprioritizes it more than it already is.
      nil ->
        reducing_priority = effective_priority(model, deprioritizations)
        if reducing_priority == :none do
          # No deprioritization
          Logger.info(
            "Focus: Model #{model.name} has no effective priority. It can't deprioritize #{competing_model_name}"
          )
          deprioritizations
        else
          competing_model = GenerativeModels.fetch!(competing_model_name)
          reduced_priority = Andy.reduce_level_by(competing_model.priority, reducing_priority)
          competing_effective_priority = effective_priority(competing_model, deprioritizations)
          if Andy.lower_level?(reduced_priority, competing_effective_priority) do
            # Competing model gets deprioritized
            Logger.info("Focus: Deprioritizing #{competing_model_name} by #{reducing_priority}")
            PubSub.notify_model_deprioritized(competing_model_name, reducing_priority)
          end
          [
            %Deprioritization{
              model_name: model.name,
              prediction_names: [prediction_name],
              competing_model_name: competing_model_name,
              from_priority: competing_model.priority,
              to_priority: reduced_priority
            }
            | deprioritizations
          ]
        end
    end
  end

  defp find_deprioritization(deprioritizations, model_name, competing_model_name) do
    Enum.find(
      deprioritizations,
      &(&1.model_name == model_name and &1.competing_model_name == competing_model_name)
    )
  end

  defp update_deprioritizations(deprioritizations, update) do
    Enum.reduce(
      deprioritizations,
      [],
      fn (deprioritization,
         acc) ->
        if equivalent?(deprioritization, update) do
          [update | acc]
        else
          [deprioritization | acc]
        end
      end
    )
  end

  # Find the possibly reduced priority of a model
  defp effective_priority(model, deprioritizations) do
    Enum.reduce(
      deprioritizations,
      model.priority,
      fn (%Deprioritization{
        competing_model_name: competing_model_name,
        to_priority: to_priority
      }, acc) ->
        if competing_model_name == model.name do
          Andy.lowest_level(acc, to_priority)
        else
          acc
        end
      end
    )
  end

  # Lose focus on a model on behalf of a prediction about that model because the prediction was validated
  defp focus_off(model_name, prediction_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info(
      "Focus: Maybe losing focus on model #{model_name} because belief prediction #{prediction_name} was validated"
    )
    updated_deprioritizations = Enum.reduce(
      deprioritizations,
      [],
      fn (%Deprioritization{ prediction_names: prediction_names } = deprioritization, acc) ->
        if deprioritization.model_name == model_name and prediction_name in prediction_names do
          updated_prediction_names = List.delete(prediction_names, prediction_name)
          if updated_prediction_names == [] do
            reduced_deprioritizations = remove_deprioritization(deprioritizations, deprioritization)
            reprioritize(
              deprioritization.competing_model_name,
              reduced_deprioritizations
            )
            reduced_deprioritizations
          else
            Logger.info(
              "Focus: Focus remaining on model #{model_name} because of predictions #{inspect updated_prediction_names}"
            )
            update_deprioritizations(
              deprioritizations,
              %Deprioritization{ deprioritization | prediction_names: updated_prediction_names }
            )
          end
        else
          [deprioritization | acc]
        end
      end
    )
    %{ state | deprioritizations: updated_deprioritizations }
  end

  # Update the priority of a model given new deprioritizations
  defp reprioritize(model_name, deprioritizations) do
    Logger.info("Reprioritizing #{model_name} given #{inspect deprioritizations}")
    effective_reduction = effective_reduction(model_name, deprioritizations)
    Logger.info("Focus: Reprioritizing #{model_name} by reducing its base priority by #{effective_reduction}")
    PubSub.notify_model_deprioritized(model_name, effective_reduction)
  end

  # Lose focus on a model because its' believer was terminated
  defp focus_off_unconditionally(model_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info("Focus: Losing any focus on #{model_name} because believer was terminated")
    { updated_deprioritizations, to_reprioritize } = Enum.reduce(
      deprioritizations,
      { [], [] },
      fn (%{
            model_name: deprioritizing_model_name,
            competing_model_name: competing_model_name
          } = deprioritization,
         { deprioritizations_acc, to_reprioritize_acc }) ->
        if deprioritizing_model_name == model_name do
          { deprioritizations_acc, [competing_model_name | to_reprioritize_acc] }
        else
          { [deprioritization | deprioritizations_acc], to_reprioritize_acc }
        end
      end
    )
    for competing_model_name <- to_reprioritize do
      reprioritize(competing_model_name, updated_deprioritizations)
    end
    %{ state | deprioritizations: updated_deprioritizations }
  end

  # Find by how much a model should now have its priority reduced given remaining deprioritizations
  defp effective_reduction(competing_model_name, deprioritizations) do
    Enum.reduce(
      deprioritizations,
      :none,
      fn (%{
            model_name: model_name,
            competing_model_name: competing
          } = _deprioritization,
         acc) ->
        if competing == competing_model_name do
          model = GenerativeModels.fetch!(model_name)
          effective_priority = effective_priority(model, deprioritizations)
          Andy.highest_level(acc, effective_priority)
        else
          acc
        end
      end
    )
  end

  # Remove a deprioritization
  defp remove_deprioritization(deprioritizations, element) do
    Enum.reduce(
      deprioritizations,
      [],
      fn (deprioritization, acc) ->
        if equivalent?(deprioritization, element) do
          acc
        else
          [deprioritization | acc]
        end
      end
    )
  end

  defp equivalent?(deprioritization, other) do
    deprioritization.model_name == other.model_name and
    deprioritization.competing_model_name == other.competing_model_name
  end

end