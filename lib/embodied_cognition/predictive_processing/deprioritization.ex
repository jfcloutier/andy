defmodule Andy.Deprioritization do
  @moduledoc "Struct describing a model deprioritization by Focus"

  defstruct model_name: nil,
            prediction_names: [],
            competing_model_name: nil,
            from_priority: nil,
            to_priority: nil

end