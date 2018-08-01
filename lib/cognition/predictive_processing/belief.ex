defmodule Andy.Belief do

  @moduledoc "Belief in a model"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct probability: 1, # initially belief is total
            as_of: nil

  def new(
      ) do
    %Belief{
      as_of: time_secs()
    }
  end

end