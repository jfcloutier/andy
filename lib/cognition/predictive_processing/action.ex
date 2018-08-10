defmodule Andy.Action do
  @moduledoc "An action to be taken by producing an intent"

  alias __MODULE__

  alias Andy.{ Intent }

  @type t :: %__MODULE__{
               intent_about: :atom,
               intent_value: any
             }

  defstruct actuator_name: nil,
              # e.g. :locomotion
            intent_name: nil,
              # e.g. :forward
            intent_value: nil # %{speed: 10, duration: 3}

  def execute(action) do
    intent = Intent.new(
      about: action.intent_about,
      value: intent_value
    )
    PubSub.notify_intended(intent)
  end

end