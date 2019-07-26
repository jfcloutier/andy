defmodule Andy.GM.GenerativeModelsSupervisor do
  @moduledoc "Supervisor of all generative models"

  @name __MODULE__
  use DynamicSupervisor

  alias Andy.GM.{GenerativeModel, GenerativeModelDef}
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @doc "Start the generative models supervisor"
  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [], name: @name)
  end

  @doc "Start a generative model"
  def start_generative_model({%GenerativeModelDef{} = gm_def, super_parent_names, sub_gm_names}) do
    DynamicSupervisor.start_child(
      @name,
      {GenerativeModel, [gm_def, super_parent_names, sub_gm_names]}
    )
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
