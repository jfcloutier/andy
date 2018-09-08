defmodule Andy.Validator do
  @moduledoc """
    Given a prediction about a conjecture, validate it when needed, and react to it being validated or invalidated."
  """
  require Logger
  alias Andy.{ PubSub, Prediction, Percept, Belief, Fulfill, Action, Intent,
               BelieversSupervisor, PredictionFulfilled, PredictionError, Recall }
  import Andy.Utils, only: [listen_to_events: 2]

  @behaviour Andy.EmbodiedCognitionAgent

  @doc "Child spec asked by DynamicSupervisor"
  def child_spec([prediction, believer_name, conjecture_name]) do
    %{
      # defaults to restart: permanent and type: :worker
      id: __MODULE__,
      start: { __MODULE__, :start_link, [prediction, believer_name, conjecture_name] }
    }
  end

  @doc "Start the embodied cognition agent responsible for a prediction in a conjecture"
  def start_link(prediction, believer_name, conjecture_name) do
    validator_name = validator_name(prediction, conjecture_name)
    case Agent.start_link(
           fn ->
             %{
               validator_name: validator_name,
               # the name of the conjecture this validator helps validate
               predicted_conjecture_name: conjecture_name,
               # name of conjecture believer making (owning) the prediction
               believer_name: believer_name,
               # the prediction made about the conjecture
               prediction: prediction,
               # By how much is the validator deprioritized?
               deprioritization: :none,
               # Is is currently fulfilled? For starters, yes
               fulfilled?: true,
               # index of the fulfillment currently being tried. Nil if none.
               fulfillment_index: nil,
               # whether disabled because of prerequisite prediction validation
               disabled: false
             }
           end,
           [name: validator_name]
         ) do
      { :ok, pid } ->
        spawn(fn -> validate(validator_name) end)
        Logger.info("Validator #{validator_name} started on #{Prediction.summary(prediction)} with pid #{inspect pid}")
        listen_to_events(pid, __MODULE__)
        { :ok, pid }
      other ->
        other
    end
  end

  @doc "Generate the validator's name from the prediction it is responsible for and the conjecture predicted"
  def validator_name(prediction, conjecture_name) do
    String.to_atom("#{prediction.name} in #{conjecture_name}")
  end

  @doc "Enlist a believer and direct attention, if appropriate"
  def validate(validator_name) do
    enlist_believer(validator_name)
    direct_attention(validator_name)
  end

  @doc "Reset - fulfillment status only"
  def reset(validator_name) do
    Logger.info("Resetting validator #{validator_name}")
    Agent.update(
      validator_name,
      # Also enable? TODO
      fn (state) ->
        %{ state | fulfilled?: false }
      end
    )
  end

  @doc """
   Release any enlisted believer and deactivate
   any current fulfillment, before being terminated"
  """
  def about_to_be_terminated(validator_name) do
    PubSub.notify_attention_off(validator_name)
    Agent.update(
      validator_name,
      fn (state) ->
        state
        |> release_believer_from_validator()
        |> deactivate_fulfillment()
      end
    )
  end

  @doc "Enable a validator (because all prerequisite predictions are validated)"
  def enable(validator_name) do
    Agent.update(
      validator_name,
      fn (%{ disabled: disabled? } = state) ->
        if disabled? do
          Logger.info("Enabling validator #{validator_name}")
          redirect_attention(state)
        else
          Logger.info("Validator #{validator_name} already enabled")
        end
        %{ state | disabled: false }
      end
    )
  end

  @doc "Disable a validator (because a prerequisite prediction is invalidated)"
  def disable(validator_name) do
    Agent.update(
      validator_name,
      fn (%{ disabled: disabled? } = state) ->
        if not disabled? do
          Logger.info("Disabling validator #{validator_name}")
          PubSub.notify_attention_off(validator_name)
        else
          Logger.info("Validator #{validator_name} already disabled")
        end
        %{ state | disabled: true }
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
            validator_name: fulfill_validator_name,
            fulfillment_index: new_fulfillment_index
          }
        },
        %{
          validator_name: validator_name,
          fulfillment_index: current_fulfillment_index
        } = state
      ) do
    # Try a given fulfillment in response to a prediction error -
    # It might instantiate a temporary conjecture believer for a fulfillment action
    if validator_name == fulfill_validator_name do
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
        { :conjecture_deprioritized, conjecture_name, priority },
        %{
          validator_name: validator_name,
          predicted_conjecture_name: predicted_conjecture_name,
          deprioritization: deprioritization
        } = state
      ) do
    if conjecture_name == predicted_conjecture_name do
      Logger.info(
        "Changing deprioritization of validator #{validator_name} from #{deprioritization} to #{
          priority
        }"
      )
      redirect_attention(state)
      %{ state | deprioritization: priority }
    else
      state
    end
  end

  def handle_event(_event, state) do
    # Logger.debug("#{__MODULE__} ignored #{inspect event}")
    state
  end

  #### Private

  # Enlist a believer if belief (or non-belief) in a conjecture is what is being predicted
  defp enlist_believer(validator_name) do
    Agent.update(
      validator_name,
      fn (%{ prediction: %{ believed: believed } = _prediction } = state) ->
        case believed do
          nil ->
            state
          { is_or_not, conjecture_name } ->
            believer_name = BelieversSupervisor.enlist_believer(conjecture_name, validator_name, is_or_not)
            %{ state | believer_name: believer_name }
        end
      end
    )
  end

  # Release any believer enlisted by the validator
  defp release_believer_from_validator(
         %{
           believer_name: believer_name,
           validator_name: validator_name
         } = state
       ) do
    Logger.info("Releasing believer from belief validator #{validator_name}")
    if believer_name != nil do
      # Spawn, else deadlock
      spawn(
        fn ->
          BelieversSupervisor.release_believer(believer_name, validator_name)
        end
      )
      %{ state | believer_name: nil }
    end
  end

  # Direct attention by detectors to the predicted perceptions, if any
  defp direct_attention(validator_name) do
    { detector_specs_list, precision } = required_detection(validator_name)
    detector_specs_list
    |> Enum.each(&(PubSub.notify_attention_on(&1, validator_name, precision)))
  end

  # Redirect attention after a deprioritization, reprioritization or enabling
  defp redirect_attention(
         %{
           validator_name: validator_name,
           prediction: prediction,
           deprioritization: deprioritization
         } = _state
       ) do
    effective_precision = reduce_precision_by(prediction.precision, deprioritization)
    Prediction.detector_specs(prediction)
    |> Enum.each(&(PubSub.notify_attention_on(&1, validator_name, effective_precision)))
  end

  # Get the specs of detectors which attention is required to make the validator's prediction
  defp required_detection(validator_name) do
    Agent.get(
      validator_name,
      fn (%{ prediction: prediction }) ->
        { Prediction.detector_specs(prediction), prediction.precision }
      end
    )
  end

  # Is a percept relevant to the validator's prediction?
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

  # Is an actuated intent relevant to the validator's prediction?
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

  # Is a belief in a conjecture relevant to the validator's prediction?
  defp belief_relevant?(
         %Belief{ conjecture_name: conjecture_name },
         %Prediction{ believed: { _is_or_not, believed_conjecture_name } = _prediction }
       ) do
    conjecture_name == believed_conjecture_name
  end

  # Only review prediction for sure if not deprioritized
  defp review_prediction(
         %{
           validator_name: validator_name,
           deprioritization: deprioritization,
           disabled: disabled?
         } = state
       ) do
    #    random = Enum.random(1..100)
    review_prediction? = not disabled?
    and case deprioritization do
                           :none -> true
                           _other -> false
                           #      :high -> false
                           #      # don't review
                           #      :medium -> random in 1..10
                           #      # review 10% of the time
                           #      :low -> random == 1..5 # review 5% of the time
                         end
    if review_prediction? do
      do_review_prediction(state)
    else
    if disabled? do
      Logger.info(
        "Not reviewing prediction this time: Validator #{validator_name} is disabled"
      )
      else
      Logger.info(
        "Not reviewing prediction this time: Validator #{validator_name} has #{deprioritization} deprioritization."
      )
      end
      state
    end
  end

  # Review the validator's prediction (is it now valid, invalid?) and react accordingly
  # by raising a predicton error or a prediction fulfilled.
  # If the prediction is fulfilled, deactivate the current fulfillment, if any,
  # and execute any post-fulfillment actions
  defp do_review_prediction(
         %{
           prediction: prediction,
           fulfilled?: was_fulfilled?,
           prediction: prediction
         } = state
       ) do
    Logger.info("Reviewing prediction #{prediction.name} by validator #{state.validator_name}")
    if prediction_fulfilled?(prediction) do
      fulfilled_state = %{ state | fulfilled?: true }
      # Notify of prediction recovered if prediction becomes true
      if not was_fulfilled? do
        Logger.info("Prediction #{prediction.name} becomes fulfilled")
        execute_actions_post_fulfillment(prediction.when_fulfilled)
      else
        Logger.info("Prediction #{prediction.name} was already fulfilled")
        fulfilled_state
      end
      # notify fulfilled and deactivate fulfillment even if already fulfilled (b/c race conditions?)
      PubSub.notify_prediction_fulfilled(prediction_fulfilled(fulfilled_state))
      deactivate_fulfillment(fulfilled_state)
    else
      unfulfilled_state = %{ state | fulfilled?: false }
      # Notify of prediction error if prediction (still) not true
      PubSub.notify_prediction_error(prediction_error(state))
      unfulfilled_state
    end
  end

  # Is the prediction fulfilled?
  defp prediction_fulfilled?(prediction) do
    believed_as_predicted?(prediction)
    and perceived_as_predicted?(prediction)
    and actuated_as_predicted?(prediction)
  end

  defp believed_as_predicted?(
         %{ believed: nil } = _prediction
       ) do
    true
  end

  # Whether the conjecture is believed in or not as predicted
  defp believed_as_predicted?(
         %{ believed: { is_or_not, conjecture_name } } = prediction
       ) do
    # A believer has the name of the conjecture it believers in.
    believes? = Recall.recall_believed?(conjecture_name)
    believed_as_predicted? = case is_or_not do
      :is ->
        believes?
      :not ->
        not believes?
    end
    PubSub.notify_believed_as_predicted(
      conjecture_name,
      prediction.name,
      believed_as_predicted?
    )
    Logger.info("Believed as predicted is #{believed_as_predicted?} that #{inspect { is_or_not, conjecture_name }}")
    believed_as_predicted?
  end

  defp perceived_as_predicted?(%{ perceived: [] } = _prediction) do
    true
  end

  # Whether or not the predicted perceptions are verified with a given precision.
  defp perceived_as_predicted?(
         %{
           perceived: perceived_list,
           precision: precision,
           name: name
         } = _prediction
       ) do
    probability = Enum.reduce(
      perceived_list,
      1.0,
      fn (perceived, acc) ->
        Recall.probability_of_perceived(perceived) * acc
      end
    )
    perceived_as_predicted? = Andy.in_probable_range?(probability, precision)
    Logger.info(
      "Perceived as predicted is #{perceived_as_predicted?} for #{name}: #{inspect perceived_list} (probability = #{
        probability
      }, precision = #{precision})"
    )
    perceived_as_predicted?
  end

  defp actuated_as_predicted?(%{ actuated: [] } = _prediction) do
    true
  end

  # Whether or not the predicted actuations are verified with a given precision.
  defp actuated_as_predicted?(%{ actuated: actuated_list, precision: precision } = _prediction) do
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

  # Make a prediction error from the state of the validator
  defp prediction_error(state) do
    PredictionError.new(
      validator_name: state.validator_name,
      conjecture_name: state.predicted_conjecture_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Prediction.count_fulfillment_options(state.prediction)
    )
  end

  # Make a prediction fulfilled from the state of the validator
  defp prediction_fulfilled(state) do
    PredictionFulfilled.new(
      validator_name: state.validator_name,
      conjecture_name: state.predicted_conjecture_name,
      prediction_name: state.prediction.name,
      fulfillment_index: state.fulfillment_index,
      fulfillment_count: Prediction.count_fulfillment_options(state.prediction)
    )
  end

  defp deactivate_fulfillment(
         %{
           fulfillment_index: nil
         } = state
       ) do
    state
  end

  # Deactivate the current fulfillment
  defp deactivate_fulfillment(
         %{
           prediction: prediction,
           validator_name: validator_name
         } = state
       ) do
    Logger.info("Deactivating fulfillment of prediction #{prediction.name}")
    # Stop any believer started when activating the current fulfillment
    if  Prediction.fulfilled_by_believing?(prediction) do
      BelieversSupervisor.release_believer(
        Prediction.fulfillment_conjecture_name(prediction),
        validator_name
      )
    end
    %{ state | fulfillment_index: nil }
  end

  defp activate_fulfillment(
         nil,
         state,
         _first_time_or_repeated
       ) do
    Logger.info("Activating no fulfillment in validator #{state.validator_name}")
    %{ state | fulfillment_index: nil }
  end

  # Activate the fulfillment option at the given index from a list of fulfillment options
  defp activate_fulfillment(
         fulfillment_index,
         %{
           prediction: prediction,
           validator_name: validator_name
         } = state,
         first_time_or_repeated
       ) do
    Logger.info("Activating fulfillment #{fulfillment_index} in validator #{validator_name}")
    if  Prediction.fulfilled_by_believing?(prediction) do
      # Believing as a fulfillment is always affirmative
      BelieversSupervisor.enlist_believer(
        Prediction.fulfillment_conjecture_name(prediction),
        validator_name,
        :is
      )
    end
    if Prediction.fulfilled_by_doing?(prediction) do
      actions = Prediction.get_actions_at(prediction, fulfillment_index)
      Enum.each(actions, &(Action.execute_action(&1, first_time_or_repeated)))
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

  # Calculate a new (effective) precision when reduce by a given conjecture priority
  defp reduce_precision_by(precision, priority) do
    case priority do
      :none ->
        precision
      _other ->
        Andy.reduce_level_by(precision, priority)
    end
  end

end