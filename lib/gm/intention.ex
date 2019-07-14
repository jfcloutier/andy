defmodule Andy.GM.Intention do
  @moduledoc "A valued intent generator"

  defstruct name: nil, # the name of the intention
            intent_name: nil, # e.g. :go_forward
            valuator: nil # fn(gm_state) -> intent value
end
