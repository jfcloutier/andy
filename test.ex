defmodule Test do

  def count_domain(
        %{
          pick: pick,
          from: actions,
          allow_duplicates: allow_duplicates?
        }
      ) do
    factor = if allow_duplicates?, do: pick, else: 1
    n = Enum.count(actions) * factor
    div(fac(n), fac(n - pick))
  end

  def get_actions_at(
        %{
          from: actions
        } = actions_generator,
        index
      ) do
    indices_perms = indices_perms(actions_generator)
    indices = Enum.at(indices_perms, index)
    Enum.map(indices, &(Enum.at(actions, &1)))
  end

  #### PRIVATE

  def permutee_indices(
        %{
          pick: pick,
          from: actions,
          allow_duplicates: allow_duplicates?
        }
      ) do
    Enum.reduce(
      1..Enum.count(actions),
      [],
      fn (i, acc) ->
        if allow_duplicates? do
          List.duplicate(i - 1, pick) ++ acc
        else
          [i - 1 | acc]
        end
      end
    )
    |> List.flatten()
    |> Enum.reverse()
  end

  def indices_perms(%{ pick: pick } = actions_generator) do
    items = permutee_indices(actions_generator)
    shuffle(items, pick)
  end

  def shuffle([], _), do: [[]]
  def shuffle(_, 0), do: [[]]
  def shuffle(list, i) do
    for x <- list, y <- shuffle(List.delete(list, x), i - 1), do: [x | y]
  end


  def fac(0), do: 1

  def fac(n) when n > 0 do
    n * fac(n - 1)
  end


end