defmodule Andy.GM.CognitionDef do
  @moduledoc "The definition of the cognition of a robot"

  defstruct generative_model_defs: [], # list of all defined generative models
            gm_graph: %{} # structural relationships between generative model defs - gm_def_name => [gm_def_name, ...]
end