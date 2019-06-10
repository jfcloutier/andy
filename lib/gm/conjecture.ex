defmodule Andy.GM.Conjecture do
  @moduledoc "Potential Belief instantiators for Percepts received from sub-GMs in a round"

  defstruct name: nil, # A unique name in the context of a generative model
            parameter_domains: %{}, # parameter_name => domain
            predictor: nil # function on a GM's beliefs (current and priors) that
                                  # 1- produces a next-round belief expected from sub-GM(s)
                                  # 2- in terms of specified parameter sub-domains


end