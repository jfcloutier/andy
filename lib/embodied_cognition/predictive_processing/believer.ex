defmodule Andy.Believer do

  @moduledoc "Track belief in a conjecture from prediction errors and fulfillments."

  require Logger
  alias Andy.{ PubSub, Belief, Prediction, Validator, BelieversSupervisor, ValidatorsSupervisor }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([conjecture]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [conjecture] }
    }
  end

  @doc "Start the embodied cognition agent responsible for believing in a conjecture"
  def start_link(conjecture) do
    believer_name = conjecture.name
    case Agent.start_link(
           fn () ->
             %{
               believer_name: believer_name,
               conjecture: conjecture,
               # prediction_name => true|false -- the believer is validated if all predictions are true
               validations: %{ },
               # the names of the believer's validators
               validator_names: [],
               # The names of the validators that enlisted this believer and whether they are validated by the conjecture being believed
               for_validators: %{ }
               # %{validator_name => :is | :not}
             }
           end,
           [name: believer_name]
         ) do
      { :ok, pid } ->
        spawn(fn -> start_validators(believer_name) end)
        PubSub.notify_believer_started(believer_name)
        Logger.info("Believer #{believer_name} started on conjecture #{conjecture.name}")
        listen_to_events(pid, __MODULE__)
        { :ok, pid }
      other ->
        other
    end
  end

  @doc "A believer is enlisted by a validator predicting that a belief is validated or not"
  def enlisted_by_validator(believer_name, validator_name, is_or_not) do
    Agent.update(
      believer_name,
      fn (%{ for_validators: for_validators } = state) ->
        %{ state | for_validators: Map.put(for_validators, validator_name, is_or_not) }
      end
    )
  end

  @doc "A believer was released by a validator"
  def released_by_validator(believer_name, validator_name) do
    Logger.info("Believer #{believer_name} released by validator #{validator_name}")
    Agent.update(
      believer_name,
      fn (%{ for_validators: for_validators } = state) ->
        %{ state | for_validators: Map.delete(for_validators, validator_name) }
      end
    )
    if obsolete?(believer_name) do
      Logger.info("Believer #{believer_name} is obsolete")
      terminate_validators(believer_name)
      BelieversSupervisor.terminate(believer_name)
      PubSub.notify_believer_terminated(believer_name)
    else
      Logger.info("Believer #{believer_name} is not obsolete. Not terminating it.")
    end
  end


  @doc "Is a believer not needed anymore?"
  def obsolete?(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ for_validators: for_validators, conjecture: conjecture }) ->
        not conjecture.hyper_prior? and Enum.empty?(for_validators)
      end
    )
  end

  @doc "Start a validator for each prediction about the conjecture"
  def start_validators(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ conjecture: conjecture } = state) ->
        validator_names = Enum.map(
          conjecture.predictions,
          fn (prediction) ->
            ValidatorsSupervisor.start_validator(prediction, believer_name, conjecture.name)
          end
        )
        validations = Enum.reduce(
          conjecture.predictions,
          %{ },
          fn (prediction, acc) ->
            Map.put(
              acc,
              prediction.name,
              Prediction.true_by_default?(prediction)
            )
          end
        )
        %{ state | validator_names: validator_names, validations: validations }
      end
    )
  end

  @doc "Reset the believer's validators"
  def reset_validators(believer_pid) do
    Agent.cast(
      believer_pid,
      fn (%{ validator_names: validator_names } = state) ->
        for validator_name <- validator_names do
          Validator.reset(validator_name)
        end
        state
      end
    )
  end

  @doc "Is this believer only enlisted by validators positively asserting the belief?"
  def predicted_to_be_validated?(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ for_validators: for_validators } = _state) ->
        Enum.all?(Map.values(for_validators), &(&1 == :is))
      end
    )
  end

  ### Cognition Agent Behaviour

  def handle_event(
        { :prediction_error, %{ conjecture_name: conjecture_name } = prediction_error },
        %{
          conjecture: conjecture
        } = state
      ) do
    if  conjecture.name == conjecture_name do
      process_prediction_error(prediction_error, state)
    else
      state
    end
  end

  def handle_event(
        { :prediction_fulfilled, %{ conjecture_name: conjecture_name } = prediction_fulfilled },
        %{
          conjecture: conjecture
        } = state
      ) do
    if  conjecture.name == conjecture_name do
      process_prediction_fulfilled(prediction_fulfilled, state)
    else
      state
    end
  end


  def handle_event(_event, state) do
    #	Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  # PRIVATE

  # Are all predictions from the conjecture been validated?
  defp all_predictions_validated?(validations) do
    Enum.all?(validations, fn ({ _, value }) -> value == true end)
  end

  # Terminate all the validators of a believer
  defp terminate_validators(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ validator_names: validator_names } = state) ->
        Enum.each(
          validator_names,
          &(ValidatorsSupervisor.terminate_validator(&1))
        )
        %{ state | validator_names: [] }
      end
    )
  end

  # Process a prediction error about the believer's conjecture
  defp process_prediction_error(prediction_error, %{ validations: validations } = state) do
    PubSub.notify_believed(Belief.new(state.conjecture.name, false))
    updated_state = %{ state | validations: Map.put(validations, prediction_error.prediction_name, false) }
    activate_or_terminate_dependent_validators(updated_state)
  end

  # Process the fulfillment of a prediction about the believer's conjecture. Perhaps activate/terminate dependent validators.
  defp process_prediction_fulfilled(
         prediction_fulfilled,
         %{
           validations: validations
         } = state
       ) do
    updated_validations = Map.put(validations, prediction_fulfilled.prediction_name, true)
    was_already_believed? = all_predictions_validated?(validations)
    if not was_already_believed? and all_predictions_validated?(updated_validations) do
      PubSub.notify_believed(Belief.new(state.conjecture.name, true))
    end
    updated_state = %{ state | validations: updated_validations }
    activate_or_terminate_dependent_validators(updated_state)
  end

  # Activate or terminate validators that need a prediction to first be true before they are activated
  defp activate_or_terminate_dependent_validators(
         %{
           believer_name: believer_name,
           validations: validations,
           conjecture: conjecture
         } = state
       ) do
    Enum.reduce(
      conjecture.predictions,
      state,
      fn (prediction, acc) ->
        case prediction.fulfill_when do
          [] ->
            # corresponding validator not dependent on siblings
            acc
          fulfill_when ->
            if predictions_validated?(fulfill_when, validations) do
              # All pre-requisite predictions for a prediction are validated, activate a validator for it
              Logger.info(
                "Starting validator for #{prediction.name} because all pre-requisites #{
                  inspect fulfill_when
                } are now valid"
              )
              validator_name = ValidatorsSupervisor.start_validator(
                prediction,
                believer_name,
                conjecture.name
              )
              %{
                acc |
                validator_names: (
                  [validator_name | acc.validator_names]
                  |> Enum.uniq())
              }
            else
              # Not all pre-requisite validators are validated for a prediction, terminate the validator for it
              validator_name = Validator.validator_name(prediction, conjecture.name)
              Logger.info(
                "Terminating validator for #{prediction.name} because some pre-requisites #{
                  inspect fulfill_when
                } are no longer valid"
              )
              ValidatorsSupervisor.terminate_validator(
                validator_name
              )
              %{ acc | validator_names: List.delete(acc.validator_names, validator_name) }
            end
        end
      end
    )
  end

  # Are all given predictions validated?
  defp predictions_validated?(prediction_names, validations) do
    Enum.all?(prediction_names, &(Map.get(validations, &1) == true))
  end

end