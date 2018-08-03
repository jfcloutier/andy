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
    { :ok, _pid } = DynamicSupervisor.start_child(@name, spec)
  end

  @doc " A predictor grabs a believer"
  def grab_believer(generative_model, predictor_pid) do
    believer_pid = case find_believer(generative_model) do
      nil ->
        { :ok, believer_pid } = start_believer(generative_model)
        believer_pid
      believer_pid ->
        believer_pid
    end
    Believer.grabbed_by_predictor(believer_pid, predictor_pid)
    believer_id
  end

  @doc " A predictor releases a believer"
  def release_believer(generative_model, predictor) do
    believer_pid = case find_believer(generative_model) do
      nil ->
        :ok
      believer_pid ->
        believer_pid
        Believer.released_by_predictor(believer_pid, predictor_pid)
    end
  end

  @doc "Find an existing supervised believer in a model"
  def find_believer(generative_model) do
    DynamicSupervisor.which_children(@name)
    |> Enum.find(
         # It is possible that instead of a pid we get :restarted if the believer is
         # being restarted. I chose to ignore that possibility.
         fn ({ _, believer_pid, _, _ }) ->
           Believer.name(believer_pid) == generative_model.name
         end
       )
  end

  def terminate(believer_pid) do
    Believer.about_to_be_terminated(believer_pid)
    DynamicSupervisor.terminate_child(@name, believer_pid)
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end