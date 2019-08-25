defmodule Andy.GM.LongTermMemory do
  @moduledoc "Preserves across shutdowns what has been learned"

  use GenServer
  require Logger

  @filename "memory.dets"

  defmodule State do
    defstruct store: nil
  end

  def start_link(_) do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Memorize"
  def store(gm_name, type, data) do
    GenServer.cast(__MODULE__, {:store, gm_name, type, data})
  end

  def recall(gm_name, type) do
    GenServer.call(__MODULE__, {:recall, gm_name, type})
  end

  @doc "Forget everything"
  def forget_everything() do
    GenServer.cast(__MODULE__, :forget_everything)
  end

  ### CALLBACKS

  def init(_) do
    {:ok, store} = :dets.open_file('#{@filename}', type: :set, repair: true)
    {:ok, %State{store: store}}
  end

  def handle_cast(
        {:store, gm_name, type, data},
        %State{store: store} = state
      ) do
    :dets.insert(store, {{gm_name, type}, data})
    {:noreply, state}
  end

  def handle_cast(:forget_everything, %State{store: store} = state) do
     :ok = :dets.delete_all_objects(store)
     {:noreply, state}
  end

  def handle_call(
        {:recall, gm_name, type},
        _from,
        %State{store: store} = state
      ) do

    reply =
      case :dets.lookup(store, {gm_name, type}) do
        {:error, reason} ->
          Logger.warn(
            "Failed to lookup stored #{type} for GM #{gm_name}: #{inspect(reason)}"
          )
          nil

        [] ->
          nil

        [{_, data}] ->
          data
      end

    {:reply, reply, state}
  end


end