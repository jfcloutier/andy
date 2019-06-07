defmodule Andy.GM.GenerativeModelDef do
  @moduledoc "A generative model"

  @default_max_round_duration 500 # half a second

  defstruct name: nil, # the unique name of a generative model
            conjectures: [], # GM conjectures
            contradictions: [], # sets of mutually-exclusive conjectures (by name) - hyper-prior
            priors: [], # names of initially believed conjectures
            max_round_duration: @default_max_round_duration # the maximum duration of a round for the GM

end