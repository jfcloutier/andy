defmodule Andy.Belief do

  @moduledoc "Belief in a model"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct model_name: model_name,
              # initially belief is 100%
            value: true,
            as_of: nil

  def new(model_name, value) do
    %Belief{
      model_name: model_name,
      value: value,
      as_of: time_secs()
    }
  end

end