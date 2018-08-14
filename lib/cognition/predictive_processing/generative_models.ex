defmodule Andy.GenerativeModels do
  @moduledoc "Dispenser of all known generative models"

  require Logger

  @name __MODULE__

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        models = Andy.generative_models()
        %{
          models: models,
          # %{model_name => %{parent_name: <name>, children_names: [<name>, ...]}
          analysis: analyse_models(models())
        }
      end
    )
    Logger.info("#{@name} started")
    { :ok, pid }
  end

  def hyper_prior_models() do
    Agent.get(
      @name,
      fn (%{ models: models }) ->
        Enum.filter(models, &(&1.hyper_prior?))
      end
    )
  end

  def model_named(name) do
    model = Agent.get(
      @name,
      fn (%{ models: models }) ->
        Enum.find(models, &(&1.name == name))
      end
    )
    if model == nil do
      raise "Generative model #{name} not found"
    else
      model
    end
  end

  @doc "Find all models that are either siblings or children of siblings of a model, but not the model or its descendants"
  def competing_model_names(model) do
    Agent.get(
      @name,
      fn (state) ->
        sibling_names = sibling_names(model.name, state.analysis)
        (Enum.map(sibling_names, &(descendant_names(&1, state.analysis))) ++ sibling_names)
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [model.name | descendant_names(model.name, state.analysis)]))
      end
    )
  end

  ### PRIVATE

  defp sibling_names(model_name, analysis) do
    model_info = Map.fetch!(analysis, model_name)
    case model_info.parent_name do
      nil ->
        []
      parent_name ->
        parent_model_info = Map.fetch!(analysis, parent_name)
        parent_model_info.children_names
        |> Enum.reject(&(&1.name == model_name))
    end
  end

  defp descendant_names(model_name, analysis) do
    model_info = Map.fetch!(analysis, model_name)
    case model_info.children_names do
      [] ->
        []
      children_names ->
        Enum.reduce(
          children_names,
          [],
          fn (child_name, acc) ->
            acc ++ descendant_names(child_name, analysis)
          end
        ) ++ children_names
    end
  end

  defp analyse_models(models) do
    roots = Enum.filter(models, &(&1.hyper_prior?))
    { analysis, _ } = Enum.reduce(
      roots,
      { %{ }, nil },
      fn (model, acc) -> analyse_model(model, acc)
      end
    )
    analysis
  end

  defp analyse_model(model, { analysis, parent_name }) do
    # No strange loops allowed
    if model.name in Map.keys(analysis) do
      { analysis, parent_name }
    else
      children = children(model)
      updated_analysis =
        Map.put(
          analysis,
          model.name,
          %{ parent_name: parent_name, children_names: Enum.map(children, &(&1.name)) }
        )
      Enum.reduce(
        children,
        { updated_analysis, model.name },
        fn (child, acc) ->
          analyse_model(child, acc)
        end
      )
    end
  end

  defp children(model) do
    Enum.reduce(
      model.predictions,
      [],
      fn (prediction, acc) ->
        predicted = case prediction.believed do
          nil ->
            []
          { _, predicted_model_name } ->
            [predicted_model_name]
        end
        to_fulfill = Enum.reduce(
          prediction.fulfillments,
          [],
          fn (fulfillment, acc1) ->
            case fulfillment.model_name do
              nil ->
                acc1
              fulfillment_model_name ->
                [fulfillment_model_name | acc1]
            end
          end
        )
        [(predicted ++ to_fulfill) | acc]
      end
    )
    |> Enum.uniq()
  end

end