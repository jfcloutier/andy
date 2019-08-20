defmodule Andy.GM.Profiles.Rover.Utils do
  alias Andy.GM.Perception

  def always_activator(opinion_or_goal) do
    fn conjecture, _rounds ->
      [
        Conjecture.activate(conjecture,
          about: :self,
          goal?: opinion_or_goal == :goal
        )
      ]
    end
  end

  # Predict no change, or some initial expectation
  def no_change_predictor(predicted_conjecture_name, default_expectations) do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      %Prediction{
        conjecture_name: predicted_conjecture_name,
        about: about,
        expectations:
          current_perceived_values(predicted_conjecture_name, about, round) ||
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
        conjecture_name,
        about,
        value_name,
        previous_rounds
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
  def numerical_value_trend([round | previous_rounds], conjecture_name, about, value_name) do
    all_values =
      all_perceived_values(
        conjecture_name,
        about,
        value_name,
        previous_rounds
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

  def current_perceived_value(
        predicted_conjecture_name,
        value_name,
        about,
        round,
        default \\ nil
      ) do
    case current_perceived_values(
           predicted_conjecture_name,
           about,
           round
         ) do
      nil ->
        default

      values ->
        Map.get(values, value_name)
    end
  end

  def current_perceived_values(
        predicted_conjecture_name,
        about,
        %Round{perceptions: perceptions},
        default_values \\ nil
      ) do
    case Enum.find(
           perceptions,
           &(Perception.subject(&1) ==
               Perception.make_subject(
                 conjecture_name: predicted_conjecture_name.name,
                 about: about
               ))
         ) do
      nil ->
        default_values

      perception ->
        Perception.values(perception)
    end
  end

  defp all_perceived_values(
         predicted_conjecture_name,
         about,
         value_name,
         rounds
       ) do
    collect_all_perceived_values(
      predicted_conjecture_name,
      about,
      value_name,
      rounds
    )
    |> Enum.reverse()
  end

  defp collect_all_perceived_values(
         _predicted_conjecture_name,
         _about,
         _value_name,
         []
       ) do
    []
  end

  defp collect_all_perceived_values(
         predicted_conjecture_name,
         about,
         value_name,
         [round | previous_rounds] = rounds
       ) do
    case current_perceived_value(
           predicted_conjecture_name,
           about,
           value_name,
           round
         ) do
      nil ->
        collect_all_perceived_values(
          predicted_conjecture_name,
          about,
          value_name,
          previous_rounds
        )

      value ->
        [
          value
          | collect_all_perceived_values(
              predicted_conjecture_name,
              about,
              value_name,
              previous_rounds
            )
        ]
    end
  end
end
