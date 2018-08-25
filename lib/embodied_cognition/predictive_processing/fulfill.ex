defmodule Andy.Fulfill do

  @moduledoc "A fullfilment option to attempt by a predictor"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct predictor_name: nil,
            fulfillment_index: nil,
            as_of: nil

  def new(predictor_name: predictor_name, fulfillment_index: new_fulfillment_index) do
    %Fulfill{
      predictor_name: predictor_name,
      fulfillment_index: new_fulfillment_index,
      as_of: time_secs()
    }
  end

end