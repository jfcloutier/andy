defmodule Andy.Fulfillment do

  @moduledoc "One possible way of fulfilling a prediction"

  alias __MODULE__
  alias Andy.{ Action, ActionsGenerator }

  @type action_sequence :: [Action.t | fun()]
  @type t :: %__MODULE__{
               conjecture_name: String.t,
               actions: [action_sequence] | ActionsGenerator.t()
               # actions or a function that produce actions
             }

  # Fulfillment name is unique within a prediction
  defstruct conjecture_name: nil,
              # and/or actions to carry out
            actions: [] # (generators of individual) actions that might fulfill a conjecture's prediction

  def from_believing(
        conjecture_name
      ) do
    %Fulfillment{
      conjecture_name: conjecture_name
    }
  end

  def from_doing(
        action_specs
      ) when is_list(action_specs) do
    if Enum.all?(action_specs, &(is_list(&1))) do
    %Fulfillment{
      actions: action_specs
    }
    else
      # a single sequence of actions
      %Fulfillment{
        actions: [action_specs]
      }
    end
  end

  def from_doing(
        %{
          pick: how_many,
          from: actions,
          allow_duplicates: allow_duplicates?
        } = _action_specs
      )  do
    %Fulfillment{
      actions: ActionsGenerator.new(
        pick: how_many,
        from: actions,
        allow_duplicates: allow_duplicates?
      )
    }
  end

  def by_believing?(%Fulfillment{ conjecture_name: conjecture_name }) do
    conjecture_name != nil
  end

  def by_doing?(%Fulfillment{ conjecture_name: conjecture_name }) do
    conjecture_name == nil
  end

  def count_options(fulfillment) do
    cond do
      by_believing?(fulfillment) ->
        1
      actions_generated?(fulfillment) ->
        ActionsGenerator.count_domain(fulfillment.actions)
      true ->
        Enum.count(fulfillment.actions)
    end
  end

  def get_actions_at(%Fulfillment{ actions: %ActionsGenerator{ } = actions_generator }, index) do
    ActionsGenerator.get_actions_at(actions_generator, index)
  end

  def get_actions_at(%Fulfillment{ actions: actions }, index) when is_list(actions) do
    Enum.at(actions, index)
  end

  ### PRIVATE

  defp actions_generated?(%Fulfillment{ actions: %ActionsGenerator{ } }) do
    true
  end

  defp actions_generated?(_fulfillment) do
    false
  end

end