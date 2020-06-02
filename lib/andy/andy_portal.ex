defmodule Andy.AndyPortal do
  @moduledoc """
    A portal to access Andy from another node.
  """

  use GenServer
  require Logger
  alias Andy.GM.GenerativeModel
  import Andy.Utils, only: [now: 0]

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

  @doc "Return index info about current and past rounds remembered by the the GM of the given name."
  def handle_call({:round_indices, gm_name, max_rounds}, _from, state) do
    agent_name = GenerativeModel.agent_name(gm_name)
    now = now()

    indices =
      Agent.get(
        agent_name,
        fn gm_state ->
          indexed_rounds = Enum.take(gm_state.rounds, max_rounds) |> Enum.with_index()

          for {round, index} <- indexed_rounds do
            if index == 0 do
              %{number: 0, seconds: 0}
            else
              %{number: index, seconds: div(now - round.completed_on, 1000)}
            end
          end
        end
      )

    {:reply, {:ok, indices}, state}
  end

  @doc "Return elements of the round at index in the format expected by AndyWorld"
  def handle_call({:round_state, gm_name, round_index}, _from, state) do
    agent_name = GenerativeModel.agent_name(gm_name)
    rounds = Agent.get(agent_name, fn gm_state -> gm_state.rounds end)
    round = Enum.at(rounds, round_index)

    round_state = [
      round_number: round.index,
      perceptions: convert_gm_elements(round.perceptions),
      predictions_in: convert_gm_elements(round.received_predictions),
      beliefs: convert_gm_elements(round.beliefs),
      prediction_errors_out: convert_gm_elements(round.prediction_errors),
      courses_of_action: convert_gm_elements(round.courses_of_action),
      efficacies: convert_gm_elements(round.efficacies_snapshot),
      conjecture_activations: convert_gm_elements(round.conjecture_activations_snapshot)
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
