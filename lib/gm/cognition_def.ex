defmodule Andy.GM.CognitionDef do
  @moduledoc "The definition of the cognition of a robot"

  alias __MODULE__

  defstruct generative_model_defs: [],
              # list of all defined generative models
            gm_graph: %{} # structural relationships between generative model defs -
  # gm_def_name => [believer_spec]
  # believer_spec :: {:gm, <name>}
  #               :: {:detector, %{class: ..., -- e.g. :sensor
  #                                type: ...,  -- e.g. :infrared
  #                                sense: ..., -- e.g. :proximity
  #                                port: ...   -- needed only if otherwise ambiguous
  #                               }
  #                  }

end