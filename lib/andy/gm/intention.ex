defmodule Andy.GM.Intention do
  @moduledoc "A valued intent generator"

  alias __MODULE__

  # e.g. :go_forward
  defstruct intent_name: nil,
            # fn(belief_values) -> intent value
            valuator: nil,
            # Can the generated intent be repeated with the same values?
            repeatable: true

  def not_repeatable?(%Intention{repeatable: repeatable?}) do
    not repeatable?
  end
end

defimpl Inspect, for: Andy.GM.Intention do
  def inspect(intention, _opts) do
    "<Intention to #{inspect(intention.intent_name)} (#{
      if intention.repeatable, do: "", else: "not "
    }repeatable)>"
  end
end
