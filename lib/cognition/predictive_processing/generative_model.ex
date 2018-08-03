defmodule Andy.GenerativeModel do

  @moduledoc "Generative model"

  alias __MODULE__

  @type t :: %__MODULE__{
               name: atom,
               description: String.t,
               predictions: [Prediction.t],
               focus: atom,
               hyper_prior?: boolean
             }

  defstruct name: nil,
            description: nil,
              # prioritized list of lists
              # so that if higher priority prediction in error, other predictions are "less care"
              # (i.e. lower precision is ok)
            predictions: [],
              # One of :total, :higher, :same
              # How much prediction precisions are lowered for sibling models
              # and their children models
            focus: :same,
              # Is it a "hyper prior" (a foundational/permanent model) or is it fulfillment-activated
            hyper_prior?: false

  def new(
        name: name,
        description: description,
        predictions: predictions,
        focus: focus,
        hyper_prior?: hyper_prior?
      ) do
    %GenerativeModel{
      name: name,
      description: description,
      predictions: predictions,
      focus: focus,
      hyper_prior?: hyper_prior?
    }
  end

  def new(
        name: name,
        description: description,
        predictions: predictions,
        focus: focus
      ) do
    %GenerativeModel{
      name: name,
      description: description,
      predictions: predictions,
      focus: focus,
      hyper_prior?: false
    }
  end


end
