defmodule Andy.GM.Cognition do
  @moduledoc "The definition of the cognition of a robot as a graph of generative model definitions and detectors"

  alias __MODULE__

  defstruct gm_defs: [],
            # list of all defined generative models
            # gm_def_name => [gm_def_name, ...]
            children: %{}

  def gm_defs_with_family(%Cognition{
        gm_defs: gm_defs,
        children: children
      }) do
    # [{gm_model_def, [sub_gm_name, ...]},...]
    Enum.reduce(
      gm_defs,
      [],
      fn gm_def, acc ->
        sub_gm_names = Map.get(children, gm_def.name, [])

        super_gm_names =
          Enum.reduce(
            children,
            [],
            fn {parent_name, children_names}, acc ->
              if gm_def.name in children_names, do: [parent_name | acc], else: acc
            end
          )

        [{gm_def, super_gm_names, sub_gm_names} | acc]
      end
    )
  end
end
