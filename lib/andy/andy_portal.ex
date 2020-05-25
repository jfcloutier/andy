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
    {:reply, {:ok, gm_tree}, state}
  end

  @doc "Return the number of past rounds remebered by the the GM of the given name."
  def handle_call({:past_rounds_count, gm_name}, _from, state) do
    count = Agent.get(gm_name, fn gm_state -> Enum.count(gm_state.rounds) - 1 end)
    {:reply, {:ok, count}, state}
  end

  @doc "Return elements of the round at index in the format expected by AndyWorld"
  def handle_call({:round_state, gm_name, round_index}, _from, state) do
    rounds = Agent.get(gm_name, fn gm_state -> gm_state.rounds end)
    round = Enum.at(rounds, round_index)

    round_state = [
      perceptions: convert_gm_elements(round.perceptions),
      predictions_in: convert_gm_elements(round.received_predictions),
      beliefs: convert_gm_elements(round.beliefs),
      courses_of_action: convert_gm_elements(round.courses_of_action),
      efficacies: convert_gm_elements(round.efficacies_snapshot)
    ]

    {:reply, {:ok, round_state}, state}
  end

  defp convert_gm_elements(list) do
    Enum.map(
      list,
      &%{label: inspect(&1), type: Andy.gm_element_type(&1), value: Map.from_struct(&1)}
    )
  end
end
