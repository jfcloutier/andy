defmodule Andy.Belief do

  @moduledoc "Belief in a conjecture"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct conjecture_name: nil,
              # initially belief is 100%
            value: true,
            as_of: nil

  def new(conjecture_name, value) do
    %Belief{
      conjecture_name: conjecture_name,
      value: value,
      as_of: time_secs()
    }
  end

end