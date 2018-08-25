defmodule Andy.GenerativeModels do
  @moduledoc "Dispenser and analyzer of all known generative models"

  require Logger

  @name __MODULE__

  @doc "Child spec as supervised worker"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the agent"
  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        models = Andy.generative_models()
        %{
          models: models,
          # %{model_name => %{parent_name: <name>, children_names: [<name>, ...]}
          family_tree: collect_family_tree(models),
          predecessors: collect_predecessors(models)
        }
      end,
      [name: @name]
    )
    Logger.info("#{@name} started")
    { :ok, pid }
  end

  @doc "Get all hyper-prior models"
  def hyper_prior_models() do
    Agent.get(
      @name,
      fn (%{ models: models }) ->
        Enum.filter(models, &(&1.hyper_prior?))
      end
    )
  end

  @doc "Fetch a model by name"
  def fetch!(name) do
    model = Agent.get(
      @name,
      fn (%{ models: models } = _state) ->
        Enum.find(models, &(&1.name == name))
      end
    )
    if model == nil do
      raise "Generative model #{name} not found"
    else
      model
    end
  end

  @doc """
  Find all models that compete with a model.
  Competing models of a model are either non-predecessor siblings or their children,
  but not the model itself or its own descendants.
  """
  def competing_model_names(model) do
    competing_model_names = Agent.get(
      @name,
      fn (state) ->
        siblings = sibling_names(model.name, state.family_tree)
        predecessors = Map.get(state.predecessors, model.name, [])
        competing_siblings = Enum.reject(siblings, &(&1 in predecessors))
        competing_descendants = Enum.map(competing_siblings, &(descendant_names(&1, state.family_tree)))
        #        Logger.info("Model #{model.name} has siblings #{inspect siblings}")
        #        Logger.info("Model #{model.name} has predecessors #{inspect predecessors}")
        #        Logger.info("Model #{model.name} has competing siblings #{inspect competing_siblings}")
        #        Logger.info("Model #{model.name} has competing descendants #{inspect competing_descendants}")
        (competing_descendants ++ competing_siblings)
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [model.name | descendant_names(model.name, state.family_tree)]))
      end
    )
    Logger.info("Model #{model.name} has competitors #{inspect competing_model_names}")
    competing_model_names
  end

  ### PRIVATE

  # Get the names of the siblings of a model
  defp sibling_names(model_name, family_tree) do
    model_info = Map.fetch!(family_tree, model_name)
    case model_info.parent_name do
      nil ->
        []
      parent_name ->
        parent_model_info = Map.fetch!(family_tree, parent_name)
        parent_model_info.children_names
        |> Enum.reject(&(&1 == model_name))
    end
  end

  # Get the names of the descendants of a model
  defp descendant_names(model_name, family_tree) do
    model_info = Map.fetch!(family_tree, model_name)
    case model_info.children_names do
      [] ->
        []
      children_names ->
        Enum.reduce(
          children_names,
          [],
          fn (child_name, acc) ->
            acc ++ descendant_names(child_name, family_tree)
          end
        ) ++ children_names
    end
  end

  # Collect the family tree for models
  defp collect_family_tree(models) do
    roots = Enum.filter(models, &(&1.hyper_prior?))
    { family_tree, _ } = Enum.reduce(
      roots,
      { %{ }, nil },
      fn (model, acc) -> analyse_parentage(model, acc, models)
      end
    )
    family_tree
  end

  # Determine the parent and children of a model. Descend recursively.
  defp analyse_parentage(model, { family_tree, parent_name }, models) do
    Logger.info("Analyzing parentage of #{model.name} given parent #{parent_name}")
    # No strange loops allowed
    if model.name in Map.keys(family_tree) do
      { family_tree, parent_name }
    else
      children = children(model, models)
      Logger.info("The parent of #{model.name}: #{parent_name}")
      Logger.info("The children of #{model.name}: #{inspect Enum.map(children, &(&1.name))}")
      updated_family_tree =
        Map.put(
          family_tree,
          model.name,
          %{
            parent_name: parent_name,
            children_names: Enum.map(children, &(&1.name))
          }
        )
      Enum.reduce(
        children,
        { updated_family_tree, model.name },
        fn (child, acc) ->
          { updated_tree, _ } = analyse_parentage(child, acc, models)
          { updated_tree, model.name }
        end
      )
    end
  end

  # Find the children of a model as the models references in the predictions and fulfillment options of the model
  defp children(model, models) do
    Enum.reduce(
      model.predictions,
      [],
      fn (prediction, acc) ->
        predicted = case prediction.believed do
          nil ->
            acc
          { _, predicted_model_name } ->
            [predicted_model_name | acc]
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
        predicted ++ to_fulfill ++ acc
      end
    )
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(
         fn (name) ->
           Enum.find(models, &(&1.name == name))
         end
       )
      # TODO - for now, until the modeling is complete
    |> Enum.reject(&(&1 == nil))
  end

  # Find the predecessors of all models.
  # The predecessors of a model are other models referenced in the model's predictions
  # that must be believed in (or not) before the model can
  defp collect_predecessors(models) do
    Enum.reduce(
      models,
      %{ },
      fn (model, acc) ->
        Enum.reduce(
          model.predictions,
          acc,
          fn (prediction, acc1) ->
            case prediction.believed do
              nil ->
                acc1
              { _, believed_model_name } ->
                prediction_predecessors = predecessor_models_of_prediction(prediction, model)
                acc_predecessors = (Map.get(acc1, believed_model_name, []) ++ prediction_predecessors)
                                   |> Enum.uniq()
                Logger.info("Adding predecessors #{inspect prediction_predecessors} to #{believed_model_name}")
                Map.put(
                  acc1,
                  believed_model_name,
                  acc_predecessors
                )
            end
          end
        )
      end
    )
  end

  # Find the names of the predecessors of a model referenced in one of the model's predictions
  defp predecessor_models_of_prediction(prediction, model) do
    Enum.reduce(
      prediction.fulfill_when,
      [],
      fn (predecessor_prediction_name, acc) ->
        case name_of_model_believed_by(predecessor_prediction_name, model) do
          nil -> acc
          believed_model_name -> [believed_model_name | acc]
        end
      end
    )
  end

  defp name_of_model_believed_by(prediction_name, model) do
    prediction = Enum.find(model.predictions, &(&1.name == prediction_name))
    case prediction.believed do
      nil ->
        nil
      { _, believed_model_name } ->
        believed_model_name
    end
  end

end