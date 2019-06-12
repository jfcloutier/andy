defmodule Andy.GM.Belief do
  @moduledoc "A belief"
  defstruct level: 0, # from 0 to 1, how much the GM believes its named conjecture
            generative_model_name: nil,
            conjecture_name: nil,
            parameter_values: %{} # conjecture_parameter_name => value
end
