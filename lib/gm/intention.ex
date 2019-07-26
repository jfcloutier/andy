defmodule Andy.GM.Intention do
  @moduledoc "A valued intent generator"

  # the name of the intention
  defstruct name: nil,
            # e.g. :go_forward
            intent_name: nil,
            # fn(gm_state) -> intent value
            valuator: nil
end
