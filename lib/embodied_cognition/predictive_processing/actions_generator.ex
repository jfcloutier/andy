defmodule Andy.ActionsGenerator do
  @moduledoc "A generator of action sequences from permutations of actions"

  alias Andy.Action
  require Logger

  alias __MODULE__

  @type t :: %__MODULE__{
          pick: non_neg_integer,
          from: [[Action.t()] | fun()]
        }

  defstruct pick: 1,
            from: []

  @doc "Make an actions generator"
  def new(
        pick: how_many,
        from: actions
      ) do
    %ActionsGenerator{
      pick: how_many,
      from: actions
    }
  end

  @doc "Count how many actions permutations can be generated"
  def count_domain(%ActionsGenerator{
        pick: pick,
        from: actions
      }) do
    n = Enum.count(actions)
    div(fac(n), fac(n - pick))
  end

  @doc "Get the actions permutation at the given index"
  def get_actions_at(
        %ActionsGenerator{
          from: actions
        } = actions_generator,
        index
      ) do
    # TODO optimize if needed - Recalculates all indices permutations everytime...
    indices_perms = indices_perms(actions_generator)
    indices = Enum.at(indices_perms, index)
    permutation = Enum.map(indices, &Enum.at(actions, &1))
    Logger.info("Got actions sequence #{inspect(permutation)} at #{index}")
    permutation
  end

  #### PRIVATE

  defp permutee_indices(%ActionsGenerator{
         from: actions
       }) do
    Enum.reduce(
      1..Enum.count(actions),
      [],
      fn i, acc ->
        [i - 1 | acc]
      end
    )
    |> List.flatten()
  end

  defp indices_perms(%ActionsGenerator{pick: pick} = actions_generator) do
    items = permutee_indices(actions_generator)
    shuffle(items, pick)
  end

  defp shuffle([], _), do: [[]]

  defp shuffle(_, 0), do: [[]]

  defp shuffle(list, i) do
    for x <- list, y <- shuffle(List.delete(list, x), i - 1), do: [x | y]
  end

  defp fac(0), do: 1

  defp fac(n) when n > 0 do
    n * fac(n - 1)
  end
end
