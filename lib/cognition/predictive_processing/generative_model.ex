defmodule Andy.GenerativeModel do

  @moduledoc "Generative model"

  alias __MODULE__

  @type t :: %__MODULE__{
               name: atom,
               description: String.t,
               predictions: [Prediction.t],
               priority: atom,
               hyper_prior?: boolean
             }

  @keys [:name, :description, :predictions, :priority, :hyper_prior?]

  defstruct name: nil,
            description: nil,
              # prioritized list of lists
              # so that if higher priority prediction in error, other predictions are "less care"
              # (i.e. lower precision is ok)
            predictions: [],
              # One of :total, :higher, :same
              # How much prediction precisions are lowered for sibling models
              # and their children models
            priority: :high,
              # Is it a "hyper prior" (a foundational/permanent model) or is it fulfillment-activated
            hyper_prior?: false

  def new(keywords) do
    Enum.reduce(
      Keyword.keys(keywords),
      %GenerativeModel{ },
      fn (key, acc) ->
        if not key in @keys, do: raise "Invalid generative model property #{key}"
        value = Keyword.get(keywords, key)
        Map.put(acc, key, value)
      end
    )
  end

end
