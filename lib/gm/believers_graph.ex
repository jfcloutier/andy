defmodule Andy.GM.BelieversGraph do
  @moduledoc "The definition of the cognition of a robot"

  alias __MODULE__

  defstruct generative_model_defs: [],
              # list of all defined generative models
            children: %{}
  # structural relationships between generative model defs -
  # gm_def_name => [believer_spec]
  # believer_spec :: {:gm, <name>}
  #               :: {:detector, %{class: ..., -- e.g. :sensor
  #                                type: ...,  -- e.g. :infrared
  #                                sense: ..., -- e.g. :proximity
  #                                port: ...   -- needed only if otherwise ambiguous
  #                               }
  #                  }

  def generative_model_defs_with_sub_believers(
        %BelieversGraph{
          generative_model_defs: generative_model_defs,
          children: children
        }
      ) do
    # [{gm_model_def, [believer_spec,...]},...]
    Enum.reduce(
      generative_model_defs,
      [],
      fn (gm_def, acc) ->
      [{gm_def, Map.get(children, gm_def.name, [])} | acc]
      end
    )
  end
end