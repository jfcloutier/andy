defmodule Andy.BelieversSupervisor do
  @moduledoc " Supervisor of dynamically started believer."

  @name __MODULE__
  use DynamicSupervisor
  alias Andy.Believer
  require Logger

  @doc "Child spec as supervised supervisor"
  def child_spec(_) do
    %{
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] },
      type: :supervisor
    }
  end

  def start_link() do
    Logger.info("Starting #{@name}")
    DynamicSupervisor.start_link(@name, [] [name: @name])
  end

  def start_believer(generative_model) do
    spec = { Believer, [generative_model] }
    { :ok, _pid } = Supervisor.start_child(@name, spec)
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end