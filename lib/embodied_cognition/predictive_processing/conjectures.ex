defmodule Andy.Conjectures do
  @moduledoc "Dispenser and analyzer of all known conjectures"

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
        conjectures = Andy.conjectures()
        %{
          conjectures: conjectures,
          # %{conjecture_name => %{parent_name: <name>, children_names: [<name>, ...]}
          family_tree: collect_family_tree(conjectures),
          predecessors: collect_predecessors(conjectures)
        }
      end,
      [name: @name]
    )
    Logger.info("#{@name} started")
    { :ok, pid }
  end

  @doc "Get all hyper-prior conjectures"
  def hyper_prior_conjectures() do
    Agent.get(
      @name,
      fn (%{ conjectures: conjectures }) ->
        Enum.filter(conjectures, &(&1.hyper_prior?))
      end
    )
  end

  @doc "Fetch a conjecture by name"
  def fetch!(name) do
    conjecture = Agent.get(
      @name,
      fn (%{ conjectures: conjectures } = _state) ->
        Enum.find(conjectures, &(&1.name == name))
      end
    )
    if conjecture == nil do
      raise " conjecture #{name} not found"
    else
      conjecture
    end
  end

  @doc """
  Find all conjectures that compete with a conjecture.
  Competing conjectures of a conjecture are conjectures of equal or lower priority that are either non-predecessor siblings
  or their children, but not the conjecture itself or its own descendants.
  """
  def competing_conjecture_names(conjecture) do
    competing_conjecture_names = Agent.get(
      @name,
      fn (state) ->
        siblings = sibling_names(conjecture.name, state.family_tree)
        predecessors = Map.get(state.predecessors, conjecture.name, [])
        # Competing siblings are siblings with lower or equal priority, and that are not in predecessors
        competing_siblings = Enum.reject(siblings, &(Andy.lower_level?(conjecture.priority, priority_from_name(&1, state))))
                             |> Enum.reject(&(&1 in predecessors))
        competing_descendants = Enum.map(competing_siblings, &(descendant_names(&1, state.family_tree)))
#        Logger.info("Conjecture #{conjecture.name} has siblings #{inspect siblings}")
#        Logger.info("Conjecture #{conjecture.name} has predecessors #{inspect predecessors}")
#        Logger.info("Conjecture #{conjecture.name} has competing siblings #{inspect competing_siblings}")
#        Logger.info("Conjecture #{conjecture.name} has competing descendants #{inspect competing_descendants}")
        (competing_descendants ++ competing_siblings)
        |> List.flatten()
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [conjecture.name | descendant_names(conjecture.name, state.family_tree)]))
      end
    )
    Logger.info("Conjecture #{conjecture.name} has competitors #{inspect competing_conjecture_names}")
    competing_conjecture_names
  end

  ### PRIVATE

  # Get the names of the siblings of a conjecture
  defp sibling_names(conjecture_name, family_tree) do
    conjecture_info = Map.fetch!(family_tree, conjecture_name)
    case conjecture_info.parent_name do
      nil ->
        []
      parent_name ->
        parent_conjecture_info = Map.fetch!(family_tree, parent_name)
        parent_conjecture_info.children_names
        |> Enum.reject(&(&1 == conjecture_name))
    end
  end

  # Get the names of the descendants of a conjecture
  defp descendant_names(conjecture_name, family_tree) do
    conjecture_info = Map.fetch!(family_tree, conjecture_name)
    case conjecture_info.children_names do
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

  # Collect the family tree for conjectures
  defp collect_family_tree(conjectures) do
    roots = Enum.filter(conjectures, &(&1.hyper_prior?))
    { family_tree, _ } = Enum.reduce(
      roots,
      { %{ }, nil },
      fn (conjecture, acc) -> analyse_parentage(conjecture, acc, conjectures)
      end
    )
    family_tree
  end

  # Determine the parent and children of a conjecture. Descend recursively.
  defp analyse_parentage(conjecture, { family_tree, parent_name }, conjectures) do
    Logger.info("Analyzing parentage of #{conjecture.name} given parent #{parent_name}")
    # No strange loops allowed
    if conjecture.name in Map.keys(family_tree) do
      { family_tree, parent_name }
    else
      children = children(conjecture, conjectures)
      Logger.info("The parent of #{conjecture.name}: #{parent_name}")
      Logger.info("The children of #{conjecture.name}: #{inspect Enum.map(children, &(&1.name))}")
      updated_family_tree =
        Map.put(
          family_tree,
          conjecture.name,
          %{
            parent_name: parent_name,
            children_names: Enum.map(children, &(&1.name))
          }
        )
      Enum.reduce(
        children,
        { updated_family_tree, conjecture.name },
        fn (child, acc) ->
          { updated_tree, _ } = analyse_parentage(child, acc, conjectures)
          { updated_tree, conjecture.name }
        end
      )
    end
  end

  # Find the children of a conjecture as the conjectures references in the predictions and fulfillment options of the conjecture
  defp children(conjecture, conjectures) do
    Enum.reduce(
      conjecture.predictions,
      [],
      fn (prediction, acc) ->
        predicted = case prediction.believed do
          nil ->
            acc
          { _, predicted_conjecture_name } ->
            [predicted_conjecture_name | acc]
        end
        to_fulfill = Enum.reduce(
          prediction.fulfillments,
          [],
          fn (fulfillment, acc1) ->
            case fulfillment.conjecture_name do
              nil ->
                acc1
              fulfillment_conjecture_name ->
                [fulfillment_conjecture_name | acc1]
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
           Enum.find(conjectures, &(&1.name == name))
         end
       )
      # TODO - for now, until the conjectureing is complete
    |> Enum.reject(&(&1 == nil))
  end

  # Find the predecessors of all conjectures.
  # The predecessors of a conjecture are other conjectures referenced in the conjecture's predictions
  # that must be believed in (or not) before the conjecture can
  defp collect_predecessors(conjectures) do
    Enum.reduce(
      conjectures,
      %{ },
      fn (conjecture, acc) ->
        Enum.reduce(
          conjecture.predictions,
          acc,
          fn (prediction, acc1) ->
            case prediction.believed do
              nil ->
                acc1
              { _, believed_conjecture_name } ->
                prediction_predecessors = predecessor_conjectures_of_prediction(prediction, conjecture)
                acc_predecessors = (Map.get(acc1, believed_conjecture_name, []) ++ prediction_predecessors)
                                   |> Enum.uniq()
                Logger.info("Adding predecessors #{inspect prediction_predecessors} to #{believed_conjecture_name}")
                Map.put(
                  acc1,
                  believed_conjecture_name,
                  acc_predecessors
                )
            end
          end
        )
      end
    )
  end

  # Find the names of the predecessors of a conjecture referenced in one of the conjecture's predictions
  defp predecessor_conjectures_of_prediction(prediction, conjecture) do
    Enum.reduce(
      prediction.fulfill_when,
      [],
      fn (predecessor_prediction_name, acc) ->
        case name_of_conjecture_believed_by(predecessor_prediction_name, conjecture) do
          nil -> acc
          believed_conjecture_name -> [believed_conjecture_name | acc]
        end
      end
    )
  end

  defp name_of_conjecture_believed_by(prediction_name, conjecture) do
    prediction = Enum.find(conjecture.predictions, &(&1.name == prediction_name))
    case prediction.believed do
      nil ->
        nil
      { _, believed_conjecture_name } ->
        believed_conjecture_name
    end
  end

  defp priority_from_name(conjecture_name, %{conjectures: conjectures} = _state) do
    conjecture = Enum.find(conjectures, &(&1.name == conjecture_name))
    conjecture.priority
  end

end