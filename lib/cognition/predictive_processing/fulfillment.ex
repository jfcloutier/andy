defmodule Andy.Fulfillment do

  @moduledoc "One possible way of fulfilling a prediction"

  alias __MODULE__
  alias Andy.Action

  @type t :: %__MODULE__{
               model_name: String.t,
               actions: [[Action.t] | fun()]
               # actions or a function that produce actions
             }

  # Fulfillment name is unique within a prediction
  defstruct model_name: nil,
              # and/or actions to carry out
            actions: [] # (generators of individual) actions that might fulfill a model's prediction

  def new(
        model_name: model_name
      ) do
    %Fulfillment{
      model_name: model_name
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
        model_name: model_name
      ) do
    %Fulfillment{
      actions: actions,
      model_name: model_name
    }
  end

end