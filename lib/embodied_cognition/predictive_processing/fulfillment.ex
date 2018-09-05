defmodule Andy.Fulfillment do

  @moduledoc "One possible way of fulfilling a prediction"

  alias __MODULE__
  alias Andy.Action

  @type t :: %__MODULE__{
               conjecture_name: String.t,
               actions: [[Action.t] | fun()]
               # actions or a function that produce actions
             }

  # Fulfillment name is unique within a prediction
  defstruct conjecture_name: nil,
              # and/or actions to carry out
            actions: [] # (generators of individual) actions that might fulfill a conjecture's prediction

  def new(
        conjecture_name: conjecture_name
      ) do
    %Fulfillment{
      conjecture_name: conjecture_name
    }
  end

  def new(
        actions: actions
      ) do
    %Fulfillment{
      actions: actions
    }
  end

  def new(
        actions: actions,
        conjecture_name: conjecture_name
      ) do
    %Fulfillment{
      actions: actions,
      conjecture_name: conjecture_name
    }
  end

end