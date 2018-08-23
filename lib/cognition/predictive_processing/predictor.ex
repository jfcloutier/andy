defmodule Andy.Predictor do
  @moduledoc "Given a prediction, verify it and generate prediction errors if not verified"

  require Logger
  alias Andy.{ PubSub, Prediction, Percept, Belief, Fulfill, Action, Intent,
               Believer, BelieversSupervisor, Memory, PredictionFulfilled, PredictionError }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.CognitionAgentBehaviour

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_name, model_name]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_name, model_name] }
    }
  end

  @doc "Start the cognition agent responsible for believing in a generative model"
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
        Logger.info("Predictor #{predictor_name} started on #{Prediction.summary(prediction)}")
        listen_to_events(pid, __MODULE__)
        { :ok, pid }
      other ->
        other
    end
  end

  def predictor_name(prediction, model_name) do
    String.to_atom("#{prediction.name} in #{model_name}")
  end

  @doc "Get the predictor's pid"
  def pid(predictor_name) do
    Agent.get(
      predictor_name,
      fn (_state) ->
        self()
      end
    )
  end

  def has_name?(predictor_pid, name) do
    Agent.get(
      predictor_pid,
      fn (%{ predictor_name: predictor_name } = _state) ->
        predictor_name == name
      end
    )
  end

  def predict(predictor_name) do
    grab_believer(predictor_name)
    direct_attention(predictor_name)
  end

  def about_to_be_terminated(predictor_name) do
    PubSub.notify_attention_off(predictor_name)
    Agent.update(
      predictor_name,
      fn (state) ->
        state
        |> release_believer_from_predictor()
        |> deactivate_fulfillment()
      end
    )
  end

  @doc """
  Return the current fulfillment index and the number of available fulfillments.
  There are effectively none if the believer owning this predictor was grabbed
  only by predictors asserting that the believer's model is not validated ({:not, model_name}).
  In other words, we don't want to do something that fulfills a prediction that validates
  a belief uniformly predicted to be false.
  """
  def fulfillment_data(predictor_name) do
     Agent.get(
      predictor_name,
      fn (%{
            believer_name: believer_name, # the believer making the prediction managed by this predictor
            fulfillment_index: fulfillment_index,
            prediction: prediction
          } = _state) ->
        if Believer.predicted_to_be_validated?(believer_name) do
          { fulfillment_index, Enum.count(prediction.fulfillments) }
        else
          { nil, 0 }
        end
      end
    )
   end

  ### Cognition Agent Behaviour

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
        updated_state = deactivate_fulfillment(state)
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

  defp grab_believer(predictor_name) do
    Agent.update(
      predictor_name,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { is_or_not, model_name } ->
            believer_name = BelieversSupervisor.grab_believer(model_name, predictor_name, is_or_not)
            %{ state | believer_name: believer_name }
        end
      end
    )
  end

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

  defp direct_attention(predictor_name) do
    { detector_specs_list, precision } = required_detection(predictor_name)
    detector_specs_list
    |> Enum.each(&(PubSub.notify_attention_on(&1, predictor_name, precision)))
  end

  defp required_detection(predictor_name) do
    Agent.get(
      predictor_name,
      fn (%{ prediction: prediction, effective_precision: effective_precision }) ->
        { Prediction.detector_specs(prediction), effective_precision }
      end
    )
  end

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

  defp belief_relevant?(
         %Belief{ model_name: model_name },
         %Prediction{ believed: { _is_or_not, believed_model_name } = _prediction }
       ) do
    model_name == believed_model_name
  end

  defp review_prediction(
         %{
           prediction: prediction,
           fulfilled?: was_fulfilled?,
           effective_precision: precision
         } = state
       ) do
    if prediction_fulfilled?(prediction, precision) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true
      if not was_fulfilled? do
        Logger.info("Prediction #{prediction.name} becomes fulfilled")
        PubSub.notify_prediction_fulfilled(
          prediction_fulfilled(fulfilled_state)
        )
        deactivate_fulfillment(fulfilled_state)
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
    believes? = Memory.recall_believed?(model_name)
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

  defp perceived_as_predicted?(%{ perceived: perceived_list } = _prediction, precision) do
    probability = Enum.reduce(
      perceived_list,
      1.0,
      fn (perceived, acc) ->
        probability_of_perceived(perceived) * acc
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

  defp actuated_as_predicted?(%{ actuated: actuated_list } = _prediction, precision) do
    probability = Enum.reduce(
      actuated_list,
      1.0,
      fn (actuated, acc) ->
        probability_of_actuated(actuated) * acc
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

  defp probability_of_perceived({ percept_about, { :sum, target_sum }, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    actual_sum = Enum.reduce(
      percepts,
      0,
      fn (%{ value: value } = _percept, acc) ->
        value + acc
      end
    )
    if target_sum == 0, do: 1.0, else: max(1.0, actual_sum / target_sum)
  end

  defp probability_of_perceived({ percept_about, { :sum, attribute, target_sum }, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    actual_sum = Enum.reduce(
      percepts,
      0,
      fn (%{ value: value } = _percept, acc) ->
        Map.get(value, attribute) + acc
      end
    )
    if target_sum == 0, do: 1.0, else: max(1.0, actual_sum / target_sum)
  end

  defp probability_of_perceived({ percept_about, predicate, time_period } = _perceived) do
    percepts = Memory.recall_percepts_since(percept_about, time_period)
    percepts_count = Enum.count(percepts)
    Logger.info("Recalled #{percepts_count} percepts matching #{inspect percept_about} over #{inspect time_period}")
    fitting_percepts = Enum.filter(percepts, &(apply_predicate(predicate, &1, percepts)))
    fitting_count = Enum.count(fitting_percepts)
    Logger.info("Fitting #{fitting_count} percepts with predicate #{inspect predicate}")
    if percepts_count == 0, do: 0, else: fitting_count / percepts_count
  end

  defp probability_of_actuated({ intent_about, { :sum, target_sum }, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    actual_sum = Enum.reduce(
      intents,
      0,
      fn (%{ value: value } = _intent, acc) ->
        value + acc
      end
    )
    if target_sum == 0, do: 1.0, else: max(1.0, actual_sum / target_sum)
  end

  defp probability_of_actuated({ intent_about, { :sum, attribute, target_sum }, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    actual_sum = Enum.reduce(
      intents,
      0,
      fn (%{ value: value } = _intent, acc) ->
        Map.get(value, attribute) + acc
      end
    )
    if target_sum == 0, do: 1.0, else: max(1.0, actual_sum / target_sum)
  end

  defp probability_of_actuated({ intent_about, { :times, target_number }, time_period } = _actuated) do
    actual_number = Memory.recall_intents_since(intent_about, time_period)
                    |> Enum.count()
    if target_number == 0, do: 1.0, else: max(1.0, actual_number / target_number)
  end

  defp probability_of_actuated({ intent_about, predicate, time_period } = _actuated) do
    intents = Memory.recall_intents_since(intent_about, time_period)
    fitting_intents = Enum.filter(intents, &(apply_predicate(predicate, &1, intents)))
    intents_count = Enum.count(intents)
    if intents_count == 0, do: 0, else: Enum.count(fitting_intents) / intents_count
  end

  defp apply_predicate({ :gt, val }, percept, _percepts) do
    percept.value > val
  end

  defp apply_predicate({ :abs_gt, val }, percept, _percepts) do
    abs(percept.value) > val
  end

  defp apply_predicate({ :lt, val }, percept, _percepts) do
    percept.value < val
  end

  defp apply_predicate({ :abs_lt, val }, percept, _percepts) do
    abs(percept.value) < val
  end

  defp apply_predicate({ :eq, val }, percept, _percepts) do
    percept.value == val
  end

  defp apply_predicate({ :neq, val }, percept, _percepts) do
    percept.value != val
  end

  defp apply_predicate({ :in, range }, percept, _percepts) do
    percept.value in range
  end

  defp apply_predicate({ :abs_in, range }, percept, _percepts) do
    abs(percept.value) in range
  end

  defp apply_predicate({ :gt, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) > val
  end

  defp apply_predicate({ :lt, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) < val
  end

  defp apply_predicate({ :eq, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) == val
  end

  defp apply_predicate({ :neq, attribute, val }, percept, _percepts) do
    Map.get(percept.value, attribute) != val
  end

  defp apply_predicate({ :in, attribute, range }, percept, _percepts) do
    Map.get(percept.value, attribute) in range
  end


  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:ascending, percept, percepts) do
    { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
    average = Enum.reduce(before, 0, &(&1.value + &2))
    percept.value >= average
  end

  # Is the value greater than or equal to the average of previous values?
  defp apply_predicate(:descending, percept, percepts) do
    { before, _ } = Enum.split_while(percepts, &(&1.id != percept.id))
    average = Enum.reduce(before, 0, &(&1.value + &2))
    percept.value <= average
  end

  defp prediction_error(state) do
    PredictionError.new(
      predictor_name: state.predictor_name,
      model_name: state.predicted_model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Enum.count(state.prediction.fulfillments)
    )
  end

  defp prediction_fulfilled(state) do
    PredictionFulfilled.new(
      predictor_name: state.predictor_name,
      model_name: state.predicted_model_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Enum.count(state.prediction.fulfillments)
    )
  end

  defp deactivate_fulfillment(
         %{
           fulfillment_index: nil
         } = state
       ) do
    state
  end

  defp deactivate_fulfillment(
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
      BelieversSupervisor.grab_believer(fulfillment.model_name, predictor_name, :is)
    end
    if fulfillment.actions != nil do
      Enum.each(fulfillment.actions, &(Action.execute_action(&1, first_time_or_repeated)))
    end
    %{ state | fulfillment_index: fulfillment_index }
  end

  defp reduce_precision_by(precision, priority) do
    case priority do
      :none ->
        precision
      _other ->
        Andy.reduce_level_by(precision, priority)
    end
  end

end