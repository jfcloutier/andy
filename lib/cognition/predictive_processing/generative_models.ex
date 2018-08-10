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
        %{ models: Andy.generative_models() }
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

  @doc "Find all models that are either siblings or children of siblings"
  def competing_model_names(model) do
    siblings = siblings(model)
    (Enum.map(siblings, &(descendants(&1))) ++ siblings)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp siblings(model) do
    # TODO
    []
  end

  defp descendants(model) do
    # TODO
    []
  end

end