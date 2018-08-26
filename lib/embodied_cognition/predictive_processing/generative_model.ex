defmodule Andy.GenerativeModel do

  @moduledoc "A generative model, with priority and predictions. Could be a hyper-prior (always active)."

  alias __MODULE__

  @type t :: %__MODULE__{
               name: atom,
               hypothesis: String.t,
               predictions: [Prediction.t],
               priority: atom,
               hyper_prior?: boolean
             }

  @keys [:name, :hypothesis, :predictions, :priority, :hyper_prior?]

  defstruct name: nil,
              # statement of the hypothesis held by the model
            hypothesis: nil,
              # Predictions that, if all true enough, validate the model's hypothesis
            predictions: [],
              # One of :high, :medium or :low
              # How much the prediction precisions will be lowered for competing models
              # when this model's hypothesis is challenged
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
