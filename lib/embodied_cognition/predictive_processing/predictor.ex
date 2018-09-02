defmodule Andy.Predictor do
  @moduledoc """
    Given a prediction about a model, validate it when needed, and react to it being validated or invalidated."
  """
  require Logger
  alias Andy.{ PubSub, Prediction, Percept, Belief, Fulfill, Action, Intent,
               BelieversSupervisor, PredictionFulfilled, PredictionError, Recall }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_name, model_name]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_name, model_name] }
    }
  end

  @doc "Start the embodied cognition agent responsible for a prediction in a generative model"
  def start_link(prediction, believer_name, model_name) do
    predictor_name = predictor_name(prediction, model_name)
    case Agent.start_link(
           fn ->
             %{
               predictor_name: predictor_name,
               # the name of the model this predictor helps validate
               predicted_model_name: model_name,
               # name of model believer making (owning) the prediction
               believer_name: believer_name,
               # the prediction made about the model
               prediction: prediction,
               # the effective precision for the prediction
               effective_precision: prediction.precision,
               # Is is currently fulfilled? For starters, yes
               fulfilled?: true,
               # index of the fulfillment currently being tried. Nil if none.
               fulfillment_index: nil
             }
           end,
           [name: predictor_name]
         ) do
      { :ok, pid } ->
        spawn(fn -> predict(predictor_name) end)
        Logger.info("Predictor #{predictor_name} started on #{Prediction.summary(prediction)} with pid #{inspect pid}")
        listen_to_events(pid, __MODULE__)
        { :ok, pid }
      other ->
        other
    end
  end

  @doc "Generate the predictor's name from the prediction it is responsible for and the model predicted"
  def predictor_name(prediction, model_name) do
    String.to_atom("#{prediction.name} in #{model_name}")
  end

  @doc "Enlist a believer and direct attention, if appropriate"
  def predict(predictor_name) do
    enlist_believer(predictor_name)
    direct_attention(predictor_name)
  end

  @doc """
   Release any enlisted believer and deactivate
   any current fulfillment, before being terminated"
  """
  def about_to_be_terminated(predictor_name) do
    PubSub.notify_attention_off(predictor_name)
    Agent.update(
      predictor_name,
      fn (state) ->
        state
        |> release_believer_from_predictor()
        |> deactivate_current_fulfillment()
      end
    )
  end

  ### Cognition Agent Behaviour

  # If the prediction is time-sensitive, review it on each clock tick
  def handle_event(
        :tick,
        %{ prediction: prediction } = state
      ) do
    if prediction.time_sensitive? do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        { :percept_memorized, %Percept{ } = percept },
        %{ prediction: prediction } = state
      ) do
    # Validate prediction if relevant
    if percept_relevant?(percept, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        { :intent_memorized, %Intent{ } = intent },
        %{ prediction: prediction } = state
      ) do
    # Validate prediction if relevant
    if intent_relevant?(intent, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        { :belief_memorized, %Belief{ } = belief },
        %{
          prediction: prediction
        } = state
      ) do
    # Validate believed if relevant
    if belief_relevant?(belief, prediction) do
      review_prediction(state)
    else
      state
    end
  end

  def handle_event(
        {
          :fulfill,
          %Fulfill{
            predictor_name: fulfill_predictor_name,
            fulfillment_index: new_fulfillment_index
          }
        },
        %{
          predictor_name: predictor_name,
          fulfillment_index: current_fulfillment_index
        } = state
      ) do
    # Try a given fulfillment in response to a prediction error -
    # It might instantiate a temporary model believer for a fulfillment action
    if predictor_name == fulfill_predictor_name do
      if new_fulfillment_index != current_fulfillment_index do
        updated_state = deactivate_current_fulfillment(state)
        activate_fulfillment(new_fulfillment_index, updated_state, :first_time)
      else
        activate_fulfillment(new_fulfillment_index, state, :repeated)
      end
    else
      state
    end
  end

  def handle_event(
        { :model_deprioritized, model_name, priority },
        %{
          predictor_name: predictor_name,
          prediction: prediction,
          predicted_model_name: predicted_model_name
        } = state
      ) do
    if model_name == predicted_model_name do
      updated_effective_precision = reduce_precision_by(prediction.precision, priority)
      Logger.info(
        "Changing effective precision of predictor #{predictor_name} from #{prediction.precision} to #{
          updated_effective_precision
        }"
      )
      %{ state | effective_precision: updated_effective_precision }
    else
      state
    end
  end

  def handle_event(_event, state) do
    # Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  #### Private

  # Enlist a believer if belief (or non-belief) in a model is what is being predicted
  defp enlist_believer(predictor_name) do
    Agent.update(
      predictor_name,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { is_or_not, model_name } ->
            believer_name = BelieversSupervisor.enlist_believer(model_name, predictor_name, is_or_not)
            %{ state | believer_name: believer_name }
        end
      end
    )
  end

  # Release any believer enlisted by the predictor
  defp release_believer_from_predictor(
         %{
           believer_name: believer_name,
           predictor_name: predictor_name
         } = state
       ) do
    Logger.info("Releasing believer from belief predictor #{predictor_name}")
    if believer_name != nil do
      # Spawn, else deadlock
      spawn(
        fn ->
          BelieversSupervisor.release_believer(believer_name, predictor_name)
        end
      )
      %{ state | believer_name: nil }
    end
  end

  # Direct attention by detectors to the predicted perceptions, if any
  defp direct_attention(predictor_name) do
    { detector_specs_list, precision } = required_detection(predictor_name)
    detector_specs_list
    |> Enum.each(&(PubSub.notify_attention_on(&1, predictor_name, precision)))
  end

  # Get the specs of detectors which attention is required to make the predictor's prediction
  defp required_detection(predictor_name) do
    Agent.get(
      predictor_name,
      fn (%{ prediction: prediction, effective_precision: effective_precision }) ->
        { Prediction.detector_specs(prediction), effective_precision }
      end
    )
  end

  # Is a percept relevant to the predictor's prediction?
  defp percept_relevant?(
         %Percept{ about: percept_about },
         %Prediction{ perceived: perceived_specs } = _prediction
       ) do
    Enum.any?(
      perceived_specs,
      fn ({ perceived_about, _predicate, _time } = _perceived_spec) ->
        Percept.about_match?(perceived_about, percept_about)
      end
    )
  end

  # Is an actuated intent relevant to the predictor's prediction?
  defp intent_relevant?(
         %Intent{ about: about },
         %Prediction{ actuated: actuated_specs } = _prediction
       ) do
    Enum.any?(
      actuated_specs,
      fn ({ intent_about, _predicate, _time } = _actuated_specs) ->
        about == intent_about
      end
    )
  end

  defp belief_relevant?(
         _belief,
         %Prediction{ believed: nil } = _prediction
       ) do
    false
  end

  # Is a belief in a model relevant to the predictor's prediction?
  defp belief_relevant?(
         %Belief{ model_name: model_name },
         %Prediction{ believed: { _is_or_not, believed_model_name } = _prediction }
       ) do
    model_name == believed_model_name
  end

  # Review the predictor's prediction (is it now valid, invalid?) and react accordingly
  # by raising a predicton error or a prediction fulfilled.
  # If the prediction is fulfilled, deactivate the current fulfillment, if any,
  # and execute any post-fulfillment actions
  defp review_prediction(
         %{
           prediction: prediction,
           fulfilled?: was_fulfilled?,
           effective_precision: precision
         } = state
       ) do
    Logger.info("Reviewing prediction #{prediction.name} by predictor #{state.predictor_name}")
    if prediction_fulfilled?(prediction, precision) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true
      if not was_fulfilled? do
        Logger.info("Prediction #{prediction.name} becomes fulfilled")
        PubSub.notify_prediction_fulfilled(
          prediction_fulfilled(fulfilled_state)
        )
        execute_actions_post_fulfillment(prediction.when_fulfilled)
        deactivate_current_fulfillment(fulfilled_state)
      else
        fulfilled_state
      end
    else
      unfulfilled_state = %{ state | fulfilled?: false }
      # Notify of prediction error if prediction (still) not true
      PubSub.notify_prediction_error(prediction_error(state))
      unfulfilled_state
    end
  end

  # Is the prediction fulfilled?
  defp prediction_fulfilled?(prediction, precision) do
    believed_as_predicted?(prediction)
    and perceived_as_predicted?(prediction, precision)
    and actuated_as_predicted?(prediction, precision)
  end

  defp believed_as_predicted?(
         %{ believed: nil } = _prediction
       ) do
    true
  end

  # Whether the model is believed in or not as predicted
  defp believed_as_predicted?(
         %{ believed: { is_or_not, model_name } } = prediction
       ) do
    # A believer has the name of the model it believers in.
    believes? = Recall.recall_believed?(model_name)
    believed_as_predicted? = case is_or_not do
      :is ->
        believes?
      :not ->
        not believes?
    end
    PubSub.notify_believed_as_predicted(
      model_name,
      prediction.name,
      believed_as_predicted?
    )
    Logger.info("Believed as predicted is #{believed_as_predicted?} that #{inspect { is_or_not, model_name }}")
    believed_as_predicted?
  end

  defp perceived_as_predicted?(%{ perceived: [] } = _prediction, _precision) do
    true
  end

  # Whether or not the predicted perceptions are verified with a given precision.
  defp perceived_as_predicted?(%{ perceived: perceived_list } = _prediction, precision) do
    probability = Enum.reduce(
      perceived_list,
      1.0,
      fn (perceived, acc) ->
        Recall.probability_of_perceived(perceived) * acc
      end
    )
    perceived_as_predicted? = Andy.in_probable_range?(probability, precision)
    Logger.info(
      "Perceived as predicted is #{perceived_as_predicted?} for #{inspect perceived_list} (probability = #{
        probability
      }, precision = #{precision})"
    )
    perceived_as_predicted?
  end

  defp actuated_as_predicted?(%{ actuated: [] } = _prediction, _precision) do
    true
  end

  # Whether or not the predicted actuations are verified with a given precision.
  defp actuated_as_predicted?(%{ actuated: actuated_list } = _prediction, precision) do
    probability = Enum.reduce(
      actuated_list,
      1.0,
      fn (actuated, acc) ->
        Recall.probability_of_actuated(actuated) * acc
      end
    )
    actuated_as_predicted? = Andy.in_probable_range?(probability, precision)
    Logger.info(
      "Actuated as predicted is #{actuated_as_predicted?} for #{inspect actuated_list} (probability = #{
        probability
      }, precision = #{precision})"
    )
    actuated_as_predicted?
  end

  # Make a prediction error from the state of the predictor
  defp prediction_error(state) do
    PredictionError.new(
      predictor_name: state.predictor_name,
      model_name: state.predicted_model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Enum.count(state.prediction.fulfillments)
    )
  end

  # Make a prediction fulfilled from the state of the predictor
  defp prediction_fulfilled(state) do
    PredictionFulfilled.new(
      predictor_name: state.predictor_name,
      model_name: state.predicted_model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Enum.count(state.prediction.fulfillments)
    )
  end

  defp deactivate_current_fulfillment(
         %{
           fulfillment_index: nil
         } = state
       ) do
    state
  end

  # Deactivate the current fulfillment
  defp deactivate_current_fulfillment(
         %{
           fulfillment_index: fulfillment_index,
           prediction: prediction,
           predictor_name: predictor_name
         } = state
       ) do
    Logger.info("Deactivating fulfillment #{fulfillment_index} of prediction #{prediction.name}")
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index)
    # Stop whatever was started when activating the current fulfillment, if any
    if  fulfillment.model_name != nil do
      # Spawn else DEADLOCK!
      spawn(
        fn ->
          BelieversSupervisor.release_believer(fulfillment.model_name, predictor_name)
        end
      )
    end
    %{ state | fulfillment_index: nil }
  end

  defp activate_fulfillment(
         nil,
         state,
         _first_time_or_repeated
       ) do
    Logger.info("Activating no fulfillment in predictor #{state.predictor_name}")
    %{ state | fulfillment_index: nil }
  end

  # Activate the fulfillment option at the given index from a list of fulfillment options
  defp activate_fulfillment(
         fulfillment_index,
         %{
           prediction: prediction,
           predictor_name: predictor_name
         } = state,
         first_time_or_repeated
       ) do
    Logger.info("Activating fulfillment #{fulfillment_index} in predictor #{predictor_name}")
    fulfillment = Enum.at(prediction.fulfillments, fulfillment_index)
    if  fulfillment.model_name != nil do
      # Believing as a fulfillment is always affirmative
      BelieversSupervisor.enlist_believer(fulfillment.model_name, predictor_name, :is)
    end
    if fulfillment.actions != nil do
      Enum.each(fulfillment.actions, &(Action.execute_action(&1, first_time_or_repeated)))
    end
    %{ state | fulfillment_index: fulfillment_index }
  end

  defp execute_actions_post_fulfillment([]) do
    :ok
  end

  # Execute the actions for when the prediction is validated
  defp execute_actions_post_fulfillment(actions) do
    Logger.info("Executing when-fulfilled actions")
    Enum.each(actions, &(Action.execute(&1.())))
  end

  # Calculate a new (effective) precision when reduce by a given model priority
  defp reduce_precision_by(precision, priority) do
    case priority do
      :none ->
        precision
      _other ->
        Andy.reduce_level_by(precision, priority)
    end
  end

end