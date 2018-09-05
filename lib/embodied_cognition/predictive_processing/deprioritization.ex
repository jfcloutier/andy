defmodule Andy.Deprioritization do
  @moduledoc "Struct describing a conjecture deprioritization by Focus"

  defstruct conjecture_name: nil,
            prediction_names: [],
            competing_conjecture_name: nil,
            from_priority: nil,
            to_priority: nil

end