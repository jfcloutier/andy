defmodule Andy.Action do
  @moduledoc "An action to be taken by producing an intent"

  alias __MODULE__

  alias Andy.{ Intent, PubSub, Memory }
  require Logger

  @type t :: %__MODULE__{
               intent_name: :atom,
               intent_value: any,
               once?: boolean,
               allow_repeating?: boolean
             }

  defstruct intent_name: nil,
              # e.g. :forward
            intent_value: nil,
              # %{speed: 10, duration: 3}
            once?: false,
            allow_repeating?: true

  @keys [:intent_name, :intent_value, :once?, :allow_repeating?]

  def new(keywords) do
    Enum.reduce(
      Keyword.keys(keywords),
      %Action{ },
      fn (key, acc) ->
        if key not in @keys, do: raise "Invalid action property #{key}"
        value = Keyword.get(keywords, key)
        Map.put(acc, key, value)
      end
    )
  end


  @doc "Execute for the first time an action produced by executing an action-generating function"
  def execute_action(action_generator, :first_time) do
    action = action_generator.()
    Logger.info("Executing action #{inspect action} for the first time")
    execute(action)
  end

  @doc "Execute again an action produced by executing an action-generating function, if the action is repeatable"
  def execute_action(action_generator, :repeated) do
    action = action_generator.()
    if not action.once?  do
      Logger.info("Executing action #{inspect action} again")
      execute(action)
    else
      Logger.info("Not repeating one-time action #{action.intent_name}")
      :ok
    end
  end

  @doc "Execute an action by publishing the intent it defines"
  def execute(
        %Action{
          intent_name: intent_name,
          intent_value: intent_value,
          allow_repeating?: allow_repeating?
        } = action
      ) do
    if allow_repeating? or Memory.recall_value_of_latest_intent(intent_name) != intent_value do
      PubSub.notify_intended(
        Intent.new(
          about: action.intent_name,
          value: action.intent_value
        )
      )
    else
      Logger.info("Not repeating action #{inspect action}")
    end
  end

end