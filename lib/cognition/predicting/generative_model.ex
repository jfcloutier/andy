defmodule Andy.GenerativeModel do

  @moduledoc "Generative model"

  alias __MODULE__

  defstruct name: nil,
            description: nil,
            # prioritized list of lists
            # so that if higher priority prediction in error, other predictions are "less care"
            # (i.e. lower precision is ok)
            predictions: [],
            # Is it a "hyper prior" or is it fulfillment-activated
            permanent: false

  def new(
        name: name,
        description: description,
        predictions: predictions,
        # How long before belief in this model becomes stale
        permanent: permanent?
      ) do
    %GenerativeModel{
      name: name,
      description: description,
      predictions: predictions,
      permanent: permanent?
    }
  end

end
