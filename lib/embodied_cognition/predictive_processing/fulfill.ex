defmodule Andy.Fulfill do
  @moduledoc "A fullfilment option to attempt by a validator"

  import Andy.Utils, only: [time_secs: 0]

  alias __MODULE__

  defstruct validator_name: nil,
            fulfillment_index: nil,
            as_of: nil

  def new(validator_name: validator_name, fulfillment_index: new_fulfillment_index) do
    %Fulfill{
      validator_name: validator_name,
      fulfillment_index: new_fulfillment_index,
      as_of: time_secs()
    }
  end
end
