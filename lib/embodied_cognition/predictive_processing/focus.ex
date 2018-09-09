defmodule Andy.Focus do
  @moduledoc """
  Responsible for modulating the effective precisions of conjecture validators
  based on the relative priorities of the conjectures with beliefs in need of being changed.
  """

  require Logger
  alias Andy.{ PubSub, Conjectures, Deprioritization }
  import Andy.Utils, only: [listen_to_events: 2]


  @name __MODULE__

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec(_) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [] }
    }
  end

  @doc "Start the agent"
  def start_link() do
    { :ok, pid } = Agent.start_link(
      fn ->
        %{
          # [%Deprioritization{}]
          deprioritizations: []
        }
      end,
      [name: @name]
    )
    listen_to_events(pid, __MODULE__)
    { :ok, pid }
  end

  ### Cognition Agent Behaviour

  def handle_event(
        { :believed_as_predicted, conjecture_name, prediction_name, false },
        state
      ) do
    focus_on(conjecture_name, prediction_name, state)
  end

  def handle_event(
        { :believed_as_predicted, conjecture_name, prediction_name, true },
        state
      ) do
    focus_off(conjecture_name, prediction_name, state)
  end

  def handle_event(
        { :believer_terminated, conjecture_name },
        state
      ) do
    focus_off_unconditionally(conjecture_name, state)
  end

  def handle_event(_event, state) do
    #		Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  ### PRIVATE

  # Focus on a conjecture, by reducing the effective precisions the validators of competing conjectures
  # (i.e. altering precision weighing), on behalf of a prediction that needs to be fulfilled about that conjecture
  defp focus_on(conjecture_name, prediction_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info(
      "Focus: Focus on conjecture #{conjecture_name} because belief prediction #{prediction_name} was invalidated: #{inspect deprioritizations}"
    )
    conjecture = Conjectures.fetch!(conjecture_name)
    competing_conjecture_names = Conjectures.competing_conjecture_names(conjecture)
    updated_deprioritizations = Enum.reduce(
      competing_conjecture_names,
      deprioritizations,
      fn (competing_conjecture_name, acc) ->
        deprioritize(competing_conjecture_name, conjecture, prediction_name, acc)
      end
    )
    Logger.info("Focused on conjecture #{conjecture_name}: #{inspect updated_deprioritizations}")
    %{ state | deprioritizations: updated_deprioritizations }
  end

  defp deprioritize(competing_conjecture_name, conjecture, prediction_name, deprioritizations) do
    case find_deprioritization(deprioritizations, conjecture.name, competing_conjecture_name) do
      # Conjecture has already deprioritized competing conjecture because of one of its unfulfilled prediction
      %Deprioritization{ prediction_names: prediction_names } = deprioritization ->
        Logger.info("Focus: Conjecture #{competing_conjecture_name} already deprioritized by #{conjecture.name}")
        update_deprioritizations(
          deprioritizations,
          %Deprioritization{
            deprioritization |
            prediction_names: (
              [prediction_name | prediction_names]
              |> Enum.uniq())
          }
        )
      # New deprioritization of competing conjecture by conjecture
      nil ->
        reducing_priority = effective_priority(conjecture, deprioritizations)
        if reducing_priority == :none do
          # No deprioritization
          Logger.info(
            "Focus: Conjecture #{conjecture.name} has no effective priority. It can't deprioritize #{
              competing_conjecture_name
            }"
          )
          deprioritizations
        else
          # Competing conjecture gets deprioritized
          Logger.info("Focus: Deprioritizing conjecture #{competing_conjecture_name} by #{reducing_priority}")
          PubSub.notify_conjecture_deprioritized(competing_conjecture_name, reducing_priority)
          [
            %Deprioritization{
              conjecture_name: conjecture.name,
              prediction_names: [prediction_name],
              competing_conjecture_name: competing_conjecture_name
            }
            | deprioritizations
          ]
        end
    end
  end

  defp find_deprioritization(deprioritizations, conjecture_name, competing_conjecture_name) do
    Enum.find(
      deprioritizations,
      &(&1.conjecture_name == conjecture_name and &1.competing_conjecture_name == competing_conjecture_name)
    )
  end

  defp update_deprioritizations(deprioritizations, update) do
    Enum.reduce(
      deprioritizations,
      [],
      fn (deprioritization,
         acc) ->
        if equivalent?(deprioritization, update) do
          [update | acc]
        else
          [deprioritization | acc]
        end
      end
    )
  end

  # Find the possibly reduced priority of a conjecture
  defp effective_priority(conjecture, deprioritizations) do
    Enum.reduce(
      deprioritizations,
      conjecture.priority,
      fn (%Deprioritization{
        conjecture_name: deprioritizing_conjecture_name,
        competing_conjecture_name: competing_conjecture_name
      }, acc) ->
        if competing_conjecture_name == conjecture.name do
          deprioritizing_conjecture = Conjectures.fetch!(deprioritizing_conjecture_name)
          to_priority = Andy.reduce_level_by(conjecture.priority, deprioritizing_conjecture.priority)
          Andy.lowest_level(acc, to_priority)
        else
          acc
        end
      end
    )
  end

  # Lose focus on a conjecture on behalf of a prediction about that conjecture because the prediction was validated
  defp focus_off(conjecture_name, prediction_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info(
      "Focus: Focus off conjecture #{conjecture_name} because belief prediction #{
        prediction_name
      } was validated: #{inspect deprioritizations}"
    )
    updated_deprioritizations = Enum.reduce(
      deprioritizations,
      [],
      fn (%Deprioritization{ prediction_names: prediction_names } = deprioritization, acc) ->
        if deprioritization.conjecture_name == conjecture_name and prediction_name in prediction_names do
          updated_prediction_names = List.delete(prediction_names, prediction_name)
          if updated_prediction_names == [] do
            reduced_deprioritizations = remove_deprioritization(deprioritizations, deprioritization)
            :ok = reprioritize(
              deprioritization.competing_conjecture_name,
              reduced_deprioritizations
            )
            reduced_deprioritizations
          else
            Logger.info(
              "Focus: Focus remaining on conjecture #{conjecture_name} because of predictions #{
                inspect updated_prediction_names
              }"
            )
            update_deprioritizations(
              deprioritizations,
              %Deprioritization{ deprioritization | prediction_names: updated_prediction_names }
            )
          end
        else
          [deprioritization | acc]
        end
      end
    )
    Logger.info("Focused off conjecture #{conjecture_name}: #{inspect updated_deprioritizations}")
    %{ state | deprioritizations: updated_deprioritizations }
  end

  # Update the priority of a conjecture given new deprioritizations. Returns :ok
  defp reprioritize(conjecture_name, deprioritizations) do
    effective_reduction = effective_reduction(conjecture_name, deprioritizations)
    Logger.info(
      "Focus: Reprioritizing conjecture #{conjecture_name} by reducing its base priority by #{effective_reduction}"
    )
    PubSub.notify_conjecture_deprioritized(conjecture_name, effective_reduction)
    # Reprioritize all competing conjectures that had been deprioritized by the now reprioritized conjecture
    Enum.each(
      deprioritizations,
      fn (%Deprioritization{
        conjecture_name: deprioritizing_contecture_name,
        competing_conjecture_name: competing_conjecture_name
      }) ->
        if conjecture_name == deprioritizing_contecture_name do
          reprioritize(competing_conjecture_name, deprioritizations)
        end
      end
    )
  end

  # Lose focus on a conjecture because its' believer was terminated
  defp focus_off_unconditionally(conjecture_name, %{ deprioritizations: deprioritizations } = state) do
    Logger.info("Focus: Focus off conjecture #{conjecture_name} unconditionally because believer was terminated")
    { updated_deprioritizations, to_reprioritize } = Enum.reduce(
      deprioritizations,
      { [], [] },
      fn (%{
            conjecture_name: deprioritizing_conjecture_name,
            competing_conjecture_name: competing_conjecture_name
          } = deprioritization,
         { deprioritizations_acc, to_reprioritize_acc }) ->
        if deprioritizing_conjecture_name == conjecture_name do
          { deprioritizations_acc, [competing_conjecture_name | to_reprioritize_acc] }
        else
          { [deprioritization | deprioritizations_acc], to_reprioritize_acc }
        end
      end
    )
    for competing_conjecture_name <- to_reprioritize do
      reprioritize(competing_conjecture_name, updated_deprioritizations)
    end
    Logger.info("Focused off conjecture #{conjecture_name} unconditionally: #{inspect updated_deprioritizations}")
    %{ state | deprioritizations: updated_deprioritizations }
  end

  # Find by how much a conjecture should now have its priority reduced given remaining deprioritizations
  defp effective_reduction(competing_conjecture_name, deprioritizations) do
    Enum.reduce(
      deprioritizations,
      :none,
      fn (%{
            conjecture_name: conjecture_name,
            competing_conjecture_name: competing
          } = _deprioritization,
         acc) ->
        if competing == competing_conjecture_name do
          conjecture = Conjectures.fetch!(conjecture_name)
          effective_priority = effective_priority(conjecture, deprioritizations)
          Andy.highest_level(acc, effective_priority)
        else
          acc
        end
      end
    )
  end

  # Remove a deprioritization
  defp remove_deprioritization(deprioritizations, element) do
    Enum.reduce(
      deprioritizations,
      [],
      fn (deprioritization, acc) ->
        if equivalent?(deprioritization, element) do
          acc
        else
          [deprioritization | acc]
        end
      end
    )
  end

  defp equivalent?(deprioritization, other) do
    deprioritization.conjecture_name == other.conjecture_name and
    deprioritization.competing_conjecture_name == other.competing_conjecture_name
  end

end