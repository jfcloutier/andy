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

  def execute(action, :first_time) do
    PubSub.notify_intended(
      Intent.new(
        about: action.intent_about,
        value: action.intent_value
      )
    )
  end

  def execute(action, :repeated) do
    if not action.once?  do
      PubSub.notify_intended(
        Intent.new(
          about: action.intent_about,
          value: action.intent_value
        )
      )
    else
      Logger.info("Not repeating one-time action #{action.intent_about}")
      :ok
    end
  end

end