defmodule Andy.Action do
  @moduledoc "An action to be taken by producing an intent"

  alias __MODULE__

  alias Andy.{ Intent, PubSub }
  require Logger

  @type t :: %__MODULE__{
               intent_name: :atom,
               intent_value: any,
               once?: boolean
             }

  defstruct intent_name: nil,
              # e.g. :forward
            intent_value: nil,
              # %{speed: 10, duration: 3}
            once?: false

  def new(
        intent_name: intent_name,
        intent_value: intent_value,
        once?: once?
      ) do
    %Action{
      intent_name: intent_name,
      intent_value: intent_value,
      once?: once?
    }
  end

  def new(
        intent_name: intent_name,
        intent_value: intent_value
      ) do
    %Action{
      intent_name: intent_name,
      intent_value: intent_value
    }
  end

  def new(
        intent_name: intent_name
      ) do
    %Action{
      intent_name: intent_name,
      intent_value: nil
    }
  end


  def execute_action(action_generator, :first_time) do
    action = action_generator.()
    Logger.info("Executing action #{inspect action} for the first time")
    execute(action)
  end

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

  def execute(action) do
    PubSub.notify_intended(
      Intent.new(
        about: action.intent_name,
        value: action.intent_value
      )
    )
  end

end