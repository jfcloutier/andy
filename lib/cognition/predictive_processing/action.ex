defmodule Andy.Action do
  @moduledoc "An action to be taken by producing an intent"

  alias __MODULE__

  @type t :: %__MODULE__{
              intent_about: :atom,
              intent_value: any,
              once: boolean
             }

  defstruct actuator_name: nil, # e.g. :locomotion
            intent_name: nil, # e.g. :forward
            intent_value: nil, # %{speed: 10, duration: 3}
            once: false # Do at most once when fulfilling?

end