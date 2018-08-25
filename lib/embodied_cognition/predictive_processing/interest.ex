defmodule Andy.Interest do
  @moduledoc """
  Responsible for modulating the effective precisions of model predictors
  based on the relative priorities of the models with beliefs in need of being changed.
  """

  require Logger
  alias Andy.{ PubSub, GenerativeModels }
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
          # %{model_name => %{ competing_model_names: deprioritized_competing_model_names,
          #                    prediction_names: [...]
          #                    priority: model_priority }
          # }
          focus: %{ }
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

  # Focus interest on a model, by reducing the effective precisions the predictors of competing models
  # (i.e. altering precision weighing), on behalf of a prediction that needs to be fulfilled about that model
  defp focus_on(model_name, prediction_name, %{ focus: focus } = state) do
    Logger.info("Focusing on model #{model_name} because belief prediction #{prediction_name} was invalidated")
    case Map.get(focus, model_name) do
      nil ->
        model = GenerativeModels.fetch!(model_name)
        competing_model_names = GenerativeModels.competing_model_names(model)
        deprioritize_competing_models(competing_model_names, model, focus)
        %{
          state |
          focus: Map.put(
            focus,
            model_name,
            %{
              competing_model_names: competing_model_names,
              prediction_names: [prediction_name],
              priority: model.priority
            }
          )
        }
      %{ prediction_names: prediction_names } = model_focus ->
        # competing models already deprioritized
        %{
          state |
          focus: Map.put(
            focus,
            model_name,
            %{
              model_focus |
              prediction_names: (
                [prediction_name | prediction_names]
                |> Enum.uniq())
            }
          )
        }
    end
  end

  # Lose interest in a model on behalf of a prediction about that model
  defp focus_off(model_name, prediction_name, %{ focus: focus } = state) do
    Logger.info("Maybe losing focus on model #{model_name} because belief prediction #{prediction_name} was validated")
    case Map.get(focus, model_name) do
      nil ->
      Logger.info("No reprioritization needed")
        # competing models already reprioritized
        state
      %{ prediction_names: prediction_names } = model_focus ->
        updated_prediction_names = List.delete(prediction_names, prediction_name)
        if Enum.count(updated_prediction_names) == 0 do
          reprioritize_competing_models(model_name, focus)
          %{ state | focus: Map.delete(focus, model_name) }
        else
          Logger.info("Focus on #{model_name} still on for predictions #{inspect updated_prediction_names}")
          %{
            state |
            focus: Map.put(
              focus,
              model_name,
              %{
                model_focus |
                prediction_names: updated_prediction_names
              }
            )
          }
        end
    end
  end

  # Lose interest in a model unconditionally
  defp focus_off_unconditionally(model_name, %{ focus: focus } = state) do
    Logger.info("Losing any focus on #{model_name} because its believer was terminated")
    case Map.get(focus, model_name) do
      nil ->
        # competing models already reprioritized
        state
      _model_focus ->
        reprioritize_competing_models(model_name, focus)
        %{ state | focus: Map.delete(focus, model_name) }
    end
  end

  # Deprioritize competing models of lower priority that have not been deprioritizeded enough
  defp deprioritize_competing_models(competing_model_names, model, focus) do
    Logger.info("Looking at deprioritizing models #{inspect competing_model_names} that compete with #{model.name}")
    to_deprioritize = competing_model_names
                      # competing models from their names
                      |> Enum.map(&(GenerativeModels.fetch!(&1)))
      # only keep competing models of lower priority
                      |> Enum.filter(&(Andy.higher_level?(model.priority, &1.priority)))
      # reject those already deprioritized enough
                      |> Enum.reject(&(already_deprioritized_enough?(&1, model.priority, focus)))
    # notify the deprioritization of applicable competing models
    Logger.info("Deprioritizing models #{inspect Enum.map(to_deprioritize, &(&1.name))} by #{model.priority}")
    Enum.each(
      to_deprioritize,
      &(PubSub.notify_model_deprioritized(&1.name, model.priority))
    )
  end

  # Update the prioritization of competing models after a model that might have deprioritized them is deactivated
  defp reprioritize_competing_models(
         deactivated_model_name,
         focus
       ) do
    %{ competing_model_names: competing_model_names } = Map.get(focus, deactivated_model_name)
    Logger.info("Reprioritizing #{inspect competing_model_names} that were competing with #{deactivated_model_name}")
    competing_model_names
    |> Enum.each(
         fn (competing_model_name) ->
           # can be :none
           max_priority = find_highest_remaining_deprioritization(focus, competing_model_name, deactivated_model_name)
           PubSub.notify_model_deprioritized(competing_model_name, max_priority)
         end
       )
  end

  # Has the competing model already been deprioritized as much or more by another model?
  defp already_deprioritized_enough?(competing_model_name, model_priority, focus) do
    Enum.any?(
      focus,
      fn ({
        _model_name,
        %{
          competing_model_names: other_competing_model_names,
          priority: other_priority
        }
      }) ->
        # other priority is higher or equal
        competing_model_name in other_competing_model_names
        and (other_priority == model_priority or Andy.higher_level?(other_priority, model_priority))
      end
    )
  end

  # Find the highest deprioritization already carried out on the competing model by some model
  # other than the one being deactivated. Return :none if none
  defp find_highest_remaining_deprioritization(focus, competing_model_name, deactivated_model_name) do
    Enum.reduce(
      focus,
      :none,
      fn ({
        model_name,
        %{
          competing_model_names: other_competing_model_names
        }
      }, acc) ->
        if model_name != deactivated_model_name and competing_model_name in other_competing_model_names do
          model = GenerativeModels.fetch!(model_name)
          Andy.highest_level(acc, model.priority)
        else
          acc
        end
      end
    )
  end

end