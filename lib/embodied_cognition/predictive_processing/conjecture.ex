defmodule Andy.Conjecture do

  @moduledoc "A conjecture, with priority and predictions. Could be a hyper-prior (always active)."

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
              # statement of the hypothesis held by the conjecture
            hypothesis: nil,
              # Predictions that, if all true enough, validate the conjecture's hypothesis
            predictions: [],
              # One of :high, :medium or :low
              # How much the prediction precisions will be lowered for competing conjectures
              # when this conjecture's hypothesis is challenged
            priority: :high,
              # Is it a "hyper prior" (a foundational/permanent conjecture) or is it fulfillment-activated
            hyper_prior?: false

  def new(keywords) do
    Enum.reduce(
      Keyword.keys(keywords),
      %Conjecture{ },
      fn (key, acc) ->
        if not key in @keys, do: raise "Invalid conjecture property #{key}"
        value = Keyword.get(keywords, key)
        Map.put(acc, key, value)
      end
    )
  end

end
