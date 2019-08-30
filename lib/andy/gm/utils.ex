defmodule Andy.GM.Utils do

  alias Andy.GM.{Perception, Belief, Prediction, Round, Intention, Conjecture}

  def always_activator(opinion_or_goal, about \\ nil)

  def always_activator(:opinion, about) do
    fn conjecture, _rounds, prediction_about ->
      [
        Conjecture.activate(conjecture,
          about: about || prediction_about,
          goal: nil
        )
      ]
    end
  end

  def always_activator(:goal, about) do
    fn conjecture, _rounds, prediction_about ->
      [
        Conjecture.activate(conjecture,
          about: about || prediction_about,
          goal: fn _belief_values -> true end
        )
      ]
    end
  end

  def constant_valuator(values) do
    fn _conjecture_activation, _rounds ->
      values
    end
  end

  def empty_valuator() do
    fn _conjecture_activation, _rounds ->
      %{}
    end
  end

  # Predict no change, or some initial expectation
  def no_change_predictor(predicted_conjecture_name, default: default_expectations) do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      %Prediction{
        conjecture_name: predicted_conjecture_name,
        about: about,
        expectations:
          current_perceived_values(round, about, predicted_conjecture_name, default: nil) ||
            default_expectations
      }
    end
  end

  # Fixed prediction (to be achieved by the goal conjecture)
  def goal_predictor(predicted_conjecture_name, goal_values) do
    fn conjecture_activation, _rounds ->
      about = conjecture_activation.about

      %Prediction{
        conjecture_name: predicted_conjecture_name,
        about: about,
        expectations: goal_values
      }
    end
  end

  # Crudely predict, from all previous rounds, the expected distribution of a named, numerical value
  def expected_numerical_value([_round | previous_rounds], conjecture_name, about, value_name) do
    all_values =
      all_perceived_values(
        previous_rounds,
        about,
        conjecture_name,
        value_name
      )
      |> Enum.filter(&is_number(&1))

    if Enum.count(all_values) == 0 do
      :unknown
    else
      average = Enum.sum(all_values) / Enum.count(all_values)
      min_value = Enum.min(all_values)
      max_value = Enum.max(all_values)
      min_deviation = min(average - min_value, max_value - average)
      [(average - min_deviation)..(average + min_deviation)]
    end
  end

  # Determine if a name value has been :increasing, :decreasing, :static, or :unknown over previous rounds
  def numerical_value_trend([_round | previous_rounds], conjecture_name, about, value_name) do
    all_values =
      all_perceived_values(
        previous_rounds,
        about,
        conjecture_name,
        value_name
      )
      |> Enum.filter(&is_number(&1))

    case all_values do
      [] ->
        :unknown

      [_value] ->
        :static

      [value, prior_value | _] ->
        cond do
          value == prior_value ->
            :static

          value < prior_value ->
            :decreasing

          true ->
            :increasing
        end
    end
  end

  def once_believed?([], _about, _conjecture_name, _value_name, _value, since: _since) do
    false
  end

  def once_believed?(
        [
          %Round{beliefs: beliefs, completed_on: completed_on} | previous_rounds
        ],
        about,
        conjecture_name,
        value_name,
        value,
        since: since
      ) do
    if completed_on < since do
      false
    else
      subject = Perception.make_subject(conjecture_name: conjecture_name, about: about)

      case Enum.find(beliefs, &(Belief.subject(&1) == subject)) do
        nil ->
          once_believed?(conjecture_name, about, value_name, value, since, previous_rounds)

        %Belief{values: values} ->
          if Map.get(values, value_name) == value do
            true
          else
            once_believed?(conjecture_name, about, value_name, value, since, previous_rounds)
          end
      end
    end
  end

  def current_perceived_value(
        round,
        about,
        predicted_conjecture_name,
        value_name,
        default: default
      ) do
    case current_perceived_values(
           round,
           about,
           predicted_conjecture_name,
           default: nil
         ) do
      nil ->
        default

      values ->
        Map.get(values, value_name)
    end
  end

  def perceived_value_range(rounds, about, conjecture_name, value_name, since: since) do
    since_rounds = Enum.filter(rounds, &{&1.completed_on >= since})

    case all_perceived_values(since_rounds, about, conjecture_name, value_name) do
      [] -> nil
      values -> [Enum.min(values)..Enum.max(values)]
    end
  end

  def current_perceived_values(
        %Round{perceptions: perceptions},
        about,
        predicted_conjecture_name,
        default: default_values
      ) do
    case Enum.find(
           perceptions,
           &(Perception.subject(&1) ==
               Perception.make_subject(
                 conjecture_name: predicted_conjecture_name,
                 about: about
               ))
         ) do
      nil ->
        default_values

      perception ->
        Perception.values(perception)
    end
  end

  def recent_perceived_values([], _about, _conjecture_name, matching: _match, since: _since) do
    []
  end

  def recent_perceived_values(
        [%Round{completed_on: completed_on, perceptions: perceptions} | previous_rounds],
        about,
        conjecture_name,
        matching: match,
        since: since
      ) do
    if completed_on < since do
      []
    else
      subject = Perception.make_subject(conjecture_name: conjecture_name, about: about)

      matching_perceptions =
        Enum.filter(
          perceptions,
          &(Perception.subject(&1) == subject and Perception.values_match?(&1, match))
        )

      matching_perceptions ++
        recent_perceived_values(previous_rounds, about, conjecture_name,
          matching: match,
          since: since
        )
    end
  end

  # The number of msecs a belief's value has been held without interruption
  def duration_believed_since(rounds, about, conjecture_name, value_name, value, latest \\ 0)

  def duration_believed_since([], _about, _conjecture_name, _value_name, _value, latest) do
    latest
  end

  def duration_believed_since(
        [%Round{completed_on: completed_on, beliefs: beliefs} | previous_rounds],
        about,
        conjecture_name,
        value_name,
        value,
        latest
      ) do
    subject = Perception.make_subject(conjecture_name: conjecture_name, about: about)

    value_believed? =
      Enum.any?(
        beliefs,
        &(Belief.subject(&1) == subject and Belief.has_value?(&1, value_name, value))
      )

    if value_believed? do
      duration_believed_since(
        previous_rounds,
        about,
        conjecture_name,
        value_name,
        value,
        completed_on
      )
    else
      latest
    end
  end

  def movement_intentions() do
    %{
      turn_right: %Intention{
        intent_name: :turn_right,
        valuator: turn_valuator(),
        repeatable: true
      },
      turn_left: %Intention{
        intent_name: :turn_left,
        valuator: turn_valuator(),
        repeatable: true
      },
      move_forward: %Intention{
        intent_name: :go_forward,
        valuator: move_valuator(),
        repeatable: true
      },
      move_back: %Intention{
        intent_name: :go_backward,
        valuator: move_valuator(),
        repeatable: true
      }
    }
  end

  def movement_domain() do
    movement_intentions() |> Map.keys()
  end

  # The number of times the value went from decreasing to increasing, increasing to decreasing, increasing to none etc.
  def variability(values) do
    changes_of_direction = find_changes_of_directions(values)
    count_changes(changes_of_direction)
  end

  def count_changes([]) do
    0
  end

  def count_changes([_]) do
    0
  end

  def count_changes([val, val | rest]) do
    count_changes([val | rest])
  end

  def count_changes([_val1, val2 | rest]) do
    count_changes([val2 | rest]) + 1
  end

  def count_perceived_since([], _about, _conjecture_name, _values, since: _since) do
    0
  end

  def count_perceived_since(
        [%Round{completed_on: completed_on, perceptions: perceptions} | previous_rounds],
        about,
        conjecture_name,
        values,
        since: since
      ) do
    if completed_on < since do
      0
    else
      subject_counted = Perception.make_subject(conjecture_name: conjecture_name, about: about)

      count =
        perceptions
        |> Enum.filter(
          &(Perception.subject(&1) == subject_counted and Perception.values_match?(&1, values))
        )
        |> Enum.count()

      count + count_perceived_since(previous_rounds, about, conjecture_name, values, since)
    end
  end

  ### PRIVATE

  defp find_changes_of_directions(values) do
    changes_of_direction(values) |> Enum.reverse()
  end

  defp changes_of_direction([]) do
    []
  end

  defp changes_of_direction([_]) do
    [:none]
  end

  defp changes_of_direction([val1, val2 | rest]) do
    change_of_direction =
      cond do
        val1 == val2 -> :none
        val1 < val2 -> :decreasing
        val1 > val2 -> :increasing
      end

    [change_of_direction | changes_of_direction([val2 | rest])]
  end

  defp all_perceived_values(
         rounds,
         about,
         predicted_conjecture_name,
         value_name
       ) do
    collect_all_perceived_values(
      rounds,
      about,
      predicted_conjecture_name,
      value_name
    )
    |> Enum.reverse()
  end

  defp collect_all_perceived_values(
         [],
         _about,
         _predicted_conjecture_name,
         _value_name
       ) do
    []
  end

  defp collect_all_perceived_values(
         [round | previous_rounds],
         about,
         predicted_conjecture_name,
         value_name
       ) do
    case current_perceived_value(
           round,
           about,
           predicted_conjecture_name,
           value_name,
           default: nil
         ) do
      nil ->
        collect_all_perceived_values(
          previous_rounds,
          about,
          predicted_conjecture_name,
          value_name
        )

      value ->
        [
          value
          | collect_all_perceived_values(
              previous_rounds,
              about,
              predicted_conjecture_name,
              value_name
            )
        ]
    end
  end

  defp turn_valuator() do
    # seconds
    2
  end

  defp move_valuator() do
    %{speed: :normal, time: 2}
  end
end
