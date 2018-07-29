defmodule Andy.Belief do

  @moduledoc "Belief in a model"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct generative_model_name: nil,
            probability: 0,
            as_of: nil

  def new(
        generative_model_name: generative_model_name,
        probability: probability
      ) do

    %Belief{
      generative_model_name: generative_model_name,
      probability: probability,
      as_of: time_secs()
    }
  end

end