defmodule Andy.GM.Action do
  @moduledoc "A valued intent generator"

  defstruct name: nil, # the name of the action
            intent: nil, # e.g. :go_forward
            valuator: nil # fn(gm_state) -> intent value
end
