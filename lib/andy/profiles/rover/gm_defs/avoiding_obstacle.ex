defmodule Andy.Profiles.Rover.GMDefs.AvoidingObstacle do
  @moduledoc "The GM definition for :avoiding_obstacle"

  alias Andy.GM.{GenerativeModelDef, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :avoiding_obstacle,
      conjectures: [
        conjecture(:obstacle_not_hit),
        conjecture(:obstacle_avoided)
      ],
      contradictions: [],
      priors: %{
        obstacle_not_hit: %{about: :self, values: %{is: true}},
        obstacle_avoided: %{about: :self, values: %{is: true}}
      },
      intentions: movement_intentions()
    }
  end

  # Conjectures

  # Self-activated goal
  defp conjecture(:obstacle_not_hit) do
    %Conjecture{
      name: :obstacle_not_hit,
      self_activated: true,
      activator: goal_activator(fn %{is: not_hit?} -> not_hit? end, :self),
      predictors: [
        no_change_predictor(:distance_to_obstacle, default: %{is: :unknown})
      ],
      valuator: obstacle_not_hit_belief_valuator(),
      intention_domain: movement_domain()
    }
  end

  # Self-activated goal
  defp conjecture(:obstacle_avoided) do
    %Conjecture{
      name: :obstacle_avoided,
      self_activated: true,
      activator: goal_activator(fn %{is: avoided?} -> avoided? end, :self),
      predictors: [
        distance_to_obstacle_predictor()
      ],
      valuator: obstacle_avoided_belief_valuator(),
      intention_domain: movement_domain()
    }
  end

  # Conjecture predictors

  def distance_to_obstacle_predictor() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about
      expectation = expected_numerical_value(rounds, :distance_to_obstacle, about, :is)

      %Prediction{
        conjecture_name: :distance_to_obstacle,
        about: about,
        expectations: Map.new([{:is, expectation}])
      }
    end
  end

  # Conjecture belief valuators

  defp obstacle_not_hit_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      distance_to_obstacle =
        current_perceived_value(round, about, :distance_to_obstacle, :is, default: :unknown)

      touched? =
        distance_to_obstacle != :unknown and
          less_than?(distance_to_obstacle, 10)

      %{is: not touched?}
    end
  end

  defp obstacle_avoided_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      approaching_obstacle? =
        current_perceived_value(round, about, :approaching_obstacle, :is, default: false)

      distance_to_obstacle =
        current_perceived_value(round, about, :distance_to_obstacle, :is, default: :unknown)

      %{
        is:
          not approaching_obstacle? and
            distance_to_obstacle != :unknown and
            greater_than?(distance_to_obstacle, 20)
      }
    end
  end
end
