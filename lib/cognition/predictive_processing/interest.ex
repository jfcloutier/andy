defmodule Andy.Interest do
  @moduledoc """
  Responsible for modulating the effective precisions of predictors
  based on the relative priorities of the models currently being realized.
  """

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
        # %{focus: %{model_name => %{competing_model_names: [competing_model_name,...],
        #                                    priority: priority}
        #                                   }
        #                   }
        %{ focus: %{ } }
      end,
      [name: @name]
    )
  end

  ### Cognition Agent Behaviour

  def register_internal() do
    PubSub.register(__MODULE__)
  end

  def handle_event(
        { :believer_started, model_name },
        %{ focus: focus } = state
      ) do
    case Map.get(focus, model_name) do
      nil ->
        model = GenerativeModels.model_named(model_name)
        competing_model_names = GenerativeModels.competing_model_names(model)
        deprioritize_competing_models(competing_model_names, model, focus)
        %{
          state |
          focus: Map.put(
            focus,
            model_name,
            %{ competing_model_names: competing_model_names, priority: model.priority }
          )
        }
      _model_focus ->
        # already deprioritized by the activated model
        state
    end
  end

  def handle_event(
        { :believer_terminated, model_name },
        %{ focus: focus } = state
      ) do
    case Map.get(focus, model_name) do
      nil ->
        # already reprioritized
        state
      _model_focus ->
        reprioritize_competing_models(model_name, focus)
        %{ state | focus: Map.delete(focus, model_name) }
    end
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  defp deprioritize_competing_models(competing_model_names, model, focus) do
    competing_model_names
    |> Enum.map(&(GenerativeModels.model_named(&1)))
    |> Enum.filter(&(Andy.higher_level?(model.priority, &1.priority)))
    |> Enum.reject(&(already_deprioritized_enough?(&1, model.priority, focus)))
    |> PubSub.notify_model_deprioritized(&1.name, model_priority)
  end

  defp reprioritize_competing_models(
         deactivated_model_name,
         focus
       ) do
    %{ competing_model_names: competing_model_names } = Map.get(focus, deactivated_model_name)
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
        (other_priority == model_priority or Andy.higher_level?(other_priority, model_priority))
        and competing_model_name in other_competing_model_names
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
          competing_model_names: other_competing_model_names,
          priority: other_priority
        }
      }) ->
        if model_name != deactivated_model_name and competing_model_name in other_competing_model_names do
          model = GenerativeModels.model_named()
          Andy.highest_level(acc, model.priority)
        else
          acc
        end
      end
    )
  end

end