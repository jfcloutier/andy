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
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      %Prediction{
        conjecture_name: predicted_conjecture_name,
        about: about,
        expectations:
          current_perceived_values(predicted_conjecture_name, about, rounds) ||
            default_expectations
      }
    end
  end

  def current_perceived_value(
        predicted_conjecture_name,
        value_name,
        about,
        rounds,
        default \\ nil
      ) do
    case current_perceived_values(
           predicted_conjecture_name,
           about,
           rounds
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
        [%Round{perceptions: perceptions}, _previous_rounds],
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
end
