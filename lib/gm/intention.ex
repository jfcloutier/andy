defmodule Andy.GM.Intention do
  @moduledoc "A valued intent generator"

  # e.g. :go_forward
  defstruct intent_name: nil,
            # fn(gm_state) -> intent value
            valuator: nil
end
