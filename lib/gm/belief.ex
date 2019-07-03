defmodule Andy.GM.Belief do
  @moduledoc "A belief from a detector or generative model"
  defstruct level: 0, # from 0 to 1, how much the GM that receives them as perceptions believes the named conjecture
            source: nil, # either {:gm, gm_name} or {:detector, %{class: ..., -- e.g. :sensor
              #                                                   type: ...,  -- e.g. :infrared
              #                                                   sense: ..., -- e.g. :proximity
              #                                                   port: ...   -- needed only if otherwise ambiguous
              #                                                   }
              #                                      }
            about: nil, # conjecture name or detector name
            parameter_values: %{}, # conjecture_parameter_name => value
            # How far the parameter values stray from predictions by super-GM(s)
            prediction_error: 0 # 1 is maximally off-prediction
end
