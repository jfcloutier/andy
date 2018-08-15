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
    { :ok, pid } = DynamicSupervisor.start_child(@name, spec)
    Believer.name(pid)
  end

  @doc " A predictor grabs a believer"
  def grab_believer(model_name, predictor_name) do
    believer_name = case find_believer_name(model_name) do
      nil ->
        model = GenerativeModels.model_named(model_name)
        { :ok, believer_name } = start_believer(model)
        believer_name
      believer_name ->
        believer_name
    end
    Believer.grabbed_by_predictor(believer_name, predictor_name)
    believer_name
  end

  @doc " A predictor releases a believer"
  def release_believer(model_name, predictor_name) do
    believer_name = case find_believer_name(model_name) do
      nil ->
        :ok
      believer_name ->
        believer_name
        Believer.released_by_predictor(believer_name, predictor_name)
    end
  end

  @doc "Find an existing supervised believer in a model"
  def find_believer_name(model_name) do
    case DynamicSupervisor.which_children(@name)
         |> Enum.find(
              # It is possible that instead of a pid we get :restarted if the believer is
              # being restarted. I chose to ignore that possibility.
              fn ({ _, pid, _, _ }) ->
                Believer.model_name(pid) == model_name
              end
            ) do
      nil ->
        nil
      { _, believer_pid, _, _ } ->
        Believer.name(believer_pid)
    end
  end

  def terminate(believer_name) do
    Believer.about_to_be_terminated(believer_name)
    DynamicSupervisor.terminate_child(@name, believer_name)
  end

  ### Callbacks

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

end