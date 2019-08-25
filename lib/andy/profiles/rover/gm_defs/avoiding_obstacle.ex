defmodule Andy.GM.Profiles.Rover.GMDefs.AvoidingObstacle do
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
      priors: %{obstacle_not_hit: %{is: true}, obstacle_avoided: %{is: true}},
      intentions: movement_intentions()
    }
  end

  # Conjectures

  defp conjecture(:obstacle_not_hit) do
    %Conjecture{
      name: :obstacle_not_hit,
      activator: obstacle_not_hit_activator(),
      predictors: [
        no_change_predictor("*:*:touch", default: %{detected: :released})
      ],
      valuator: obstacle_not_hit_valuator(),
      intention_domain: movement_domain()
    }
  end

  defp conjecture(:obstacle_avoided) do
    %Conjecture{
      name: :obstacle_avoided,
      activator: obstacle_avoided_activator(),
      predictors: [
        goal_predictor(:approaching_obstacle, %{is: false}),
        distance_to_obstacle_predictor()
      ],
      valuator: obstacle_avoided_valuator(),
      intention_domain: movement_domain()
    }
  end

  # Conjecture activators

  defp obstacle_not_hit_activator() do
    fn conjecture, [round, _previous_rounds] ->
      touched? = current_perceived_value(round, :self, :touched, :is, default: false)

      if touched? do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal: fn %{is: not_hit?} -> not_hit? end
          )
        ]
      else
        []
      end
    end
  end

  defp obstacle_avoided_activator() do
    fn conjecture, [round, _previous_rounds] ->
      approaching_obstacle? =
        current_perceived_value(round, :self, :approaching_obstacle, :is, default: false)

      distance_to_obstacle =
        current_perceived_value(round, :self, :distance_to_obstacle, :is, default: :unknown)

      if approaching_obstacle? and distance_to_obstacle != :unknown and distance_to_obstacle <= 10 do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal: fn %{is: avoided?} -> avoided? end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  def distance_to_obstacle_predictor() do
    fn conjecture_activation, rounds ->
    about = conjecture_activation.about
      expectation = expected_numerical_value(rounds, :distance_to_obstacle, about, :is)
      %Prediction{
        conjecture_name: :distance_to_obstacle,
        about: about,
        expectations: Map.new({:is, expectation})
      }
    end
  end

  # Conjecture belief valuators

  defp obstacle_not_hit_valuator() do
    fn conjecture_activation, [round, _previous_rounds] ->
      about = conjecture_activation.about

      touched? = current_perceived_value(round, about, "*:*:touch", :detected, default: :released) == :touched

      approaching_obstacle? =
        current_perceived_value(round, about, :approaching_obstacle, :is, default: false)

      %{is: not touched? and not approaching_obstacle?}
    end
  end

  defp obstacle_avoided_valuator() do
    fn conjecture_activation, [round, _previous_rounds] ->
      about = conjecture_activation.about

      approaching_obstacle? =
        current_perceived_value(round, about, :approaching_obstacle, :is, default: false)

      distance_to_obstacle =
        current_perceived_value(round, about, :distance_to_obstacle, :is, default: :unknown)

      %{
        is:
          not approaching_obstacle? and (distance_to_obstacle == :unknown or distance_to_obstacle > 10)
      }
    end
  end

  # Intention valuators


end
