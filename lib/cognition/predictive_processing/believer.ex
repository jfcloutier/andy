defmodule Andy.Believer do

  @moduledoc "Track belief in a generative model from prediction errors and fulfillments."

  require Logger
  alias Andy.{ PubSub, Belief, Predictor, BelieversSupervisor, PredictorsSupervisor }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([generative_model]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [generative_model] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
  def start_link(generative_model) do
    believer_name = generative_model.name
    case Agent.start_link(
           fn () ->
             %{
               believer_name: believer_name,
               model: generative_model,
               # prediction_name => true|false -- the believer is validated if all predictions are true
               validations: %{ },
               # the names of the believer's predictors
               predictor_names: [],
               # The names of the predictors that grabbed this believer and whether they are validated by the model being believed
               for_predictors: %{ }
               # %{predictor_name => :is | :not}
             }
           end,
           [name: believer_name]
         ) do
      { :ok, pid } ->
        spawn(fn -> start_predictors(believer_name) end)
        PubSub.notify_believer_started(believer_name)
        Logger.info("Believer #{believer_name} started on generative model #{generative_model.name}")
        listen_to_events(pid, __MODULE__)
        { :ok, pid }
      other ->
        other
    end
  end

  @doc "A believer was pressed into duty by a predictor predicting that a belief is validated or not"
  def grabbed_by_predictor(believer_name, predictor_name, is_or_not) do
    Agent.update(
      believer_name,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: Map.put(for_predictors, predictor_name, is_or_not) }
      end
    )
  end

  @doc "A believer was released by a predictor"
  def released_by_predictor(believer_name, predictor_name) do
    Logger.info("Believer #{believer_name} released by predictor #{predictor_name}")
    Agent.update(
      believer_name,
      fn (%{ for_predictors: for_predictors } = state) ->
        %{ state | for_predictors: Map.delete(for_predictors, predictor_name) }
      end
    )
    if obsolete?(believer_name) do
      Logger.info("Believer #{believer_name} is obsolete")
      terminate_predictors(believer_name)
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
      fn (%{ for_predictors: for_predictors, model: model }) ->
        not model.hyper_prior? and Enum.empty?(for_predictors)
      end
    )
  end

  @doc "Start a predictor for each prediction about the model"
  def start_predictors(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ model: model } = state) ->
        predictor_names = Enum.map(
          model.predictions,
          fn (prediction) ->
            PredictorsSupervisor.start_predictor(prediction, believer_name, model.name)
          end
        )
        validations = Enum.reduce(
          model.predictions,
          %{ },
          fn (prediction, acc) ->
            Map.put(acc, prediction.name, true)
          end
        )
        %{ state | predictor_names: predictor_names, validations: validations }
      end
    )
  end

  @doc "Is this believer only grabbed by predictors positively asserting the belief?"
  def predicted_to_be_validated?(believer_name) do
    Agent.get(
      believer_name,
      fn (%{ for_predictors: for_predictors } = _state) ->
        Enum.all?(Map.values(for_predictors), &(&1 == :is))
      end
    )
  end

  ### Cognition Agent Behaviour

  def handle_event(
        { :prediction_error, %{ model_name: model_name } = prediction_error },
        %{
          model: model
        } = state
      ) do
    if  model.name == model_name do
      process_prediction_error(prediction_error, state)
    else
      state
    end
  end

  def handle_event(
        { :prediction_fulfilled, %{ model_name: model_name } = prediction_fulfilled },
        %{
          model: model
        } = state
      ) do
    if  model.name == model_name do
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

  # Are all predictions from the model been validated?
  defp all_predictions_validated?(validations) do
    Enum.all?(validations, fn ({ _, value }) -> value == true end)
  end

  # Terminate all the predictors of a believer
  defp terminate_predictors(believer_name) do
    Agent.update(
      believer_name,
      fn (%{ predictor_names: predictor_names } = state) ->
        Enum.each(
          predictor_names,
          &(PredictorsSupervisor.terminate_predictor(&1))
        )
        %{ state | predictor_names: [] }
      end
    )
  end

  # Process a prediction error about the believer's model
  defp process_prediction_error(prediction_error, %{ validations: validations } = state) do
    PubSub.notify_believed(Belief.new(state.model.name, false))
    updated_state = %{ state | validations: Map.put(validations, prediction_error.prediction_name, false) }
    activate_or_terminate_dependent_predictors(updated_state)
  end

  # Process the fulfimmnet of a prediction about the believer's model. Perhaps activate/terminate dependent predictors.
  defp process_prediction_fulfilled(
         prediction_fulfilled,
         %{
           validations: validations
         } = state
       ) do
    updated_validations = Map.put(validations, prediction_fulfilled.prediction_name, true)
    was_already_believed? = all_predictions_validated?(validations)
    if not was_already_believed? and all_predictions_validated?(updated_validations) do
      PubSub.notify_believed(Belief.new(state.model.name, true))
    end
    updated_state = %{ state | validations: updated_validations }
    activate_or_terminate_dependent_predictors(updated_state)
  end

  # Activate or terminate predictors that need a prediction to first be true before they are activated
  defp activate_or_terminate_dependent_predictors(
         %{
           believer_name: believer_name,
           validations: validations,
           model: model
         } = state
       ) do
    Enum.reduce(
      model.predictions,
      state,
      fn (prediction, acc) ->
        case prediction.fulfill_when do
          [] ->
            # corresponding predictor not dependent on siblings
            acc
          fulfill_when ->
            if predictions_validated?(fulfill_when, validations) do
              # All pre-requisite predictions for a prediction are validated, activate a predictor for it
              Logger.info(
                "Starting predictor for #{prediction.name} because all pre-requisites #{
                  inspect fulfill_when
                } are now valid"
              )
              predictor_name = PredictorsSupervisor.start_predictor(
                prediction,
                believer_name,
                model.name
              )
              %{
                acc |
                predictor_names: (
                  [predictor_name | acc.predictor_names]
                  |> Enum.uniq())
              }
            else
              # Not all pre-requisite predictors are validated for a prediction, terminate the predictor for it
              predictor_name = Predictor.predictor_name(prediction, model.name)
              Logger.info(
                "Terminating predictor for #{prediction.name} because some pre-requisites #{
                  inspect fulfill_when
                } are no longer valid"
              )
              PredictorsSupervisor.terminate_predictor(
                predictor_name
              )
              %{ acc | predictor_names: List.delete(acc.predictor_names, predictor_name) }
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