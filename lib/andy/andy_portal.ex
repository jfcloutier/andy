defmodule Andy.AndyPortal do
  @moduledoc """
    A portal to access Andy from another node.
  """

  use GenServer
  require Logger

  @name :andy_portal

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link() do
    Logger.info("Starting #{inspect(__MODULE__)}")
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:gm_tree, _from, state) do
    gm_tree = Andy.cognition() |> Map.fetch!(:children)
    {:reply, {:ok, gm_tree}, state }
  end
end
