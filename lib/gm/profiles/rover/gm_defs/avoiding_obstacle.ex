defmodule Andy.GM.Profiles.Rover.GMDefs.AvoidingObstacle do
  @moduledoc "The GM definition for :avoiding_obstacle"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Profiles.Rover.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :avoiding_obstacle,
      conjectures: [
        conjecture(:obstacle_not_hit),
        conjecture(:obstacle_avoided)
      ],
      contradictions: [],
      priors: %{obstacle_not_hit: %{is: true}, obstacle_avoided: %{is: true}},
      intentions: %{
        turn_away: %Intention{
          intent_name: :turn_right,
          valuator: turn_valuator(),
          repeatable: true
        },
        turn_away: %Intention{
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
    }
  end

  # Conjectures

  defp conjecture(:obstacle_not_hit) do
    %Conjecture{
      name: :obstacle_not_hit,
      activator: obstacle_not_hit_activator(),
      predictors: [
        no_change_predictor("*:*:touch", %{detected: :released})
      ],
      valuator: obstacle_not_hit_valuator(),
      intention_domain: [:turn_away, :move_forward, :move_back]
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
      intention_domain: [:turn_away, :move_forward, :move_back]
    }
  end

  # Conjecture activators

  defp obstacle_not_hit_activator() do
    fn conjecture, rounds ->
      touched? = current_perceived_value(:touched, :is, about, rounds, false)

      if touched? do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal?: true
          )
        ]
      else
        []
      end
    end
  end

  defp obstacle_avoided_activator() do
    fn conjecture, rounds ->
      approaching_obstacle? =
        current_perceived_value(:approaching_obstacle, :is, about, rounds, false)

      distance_to_obstacle =
        current_perceived_value(:distance_to_obstacle, :is, about, rounds, :unknown)

      if distance_to_obstacle != :unknown and distance_to_obstacle <= 10 do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal?: true
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
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      touched? = current_perceived_value("*:*:touch", :detected, about, rounds, :released) == :touched

      approaching_obstacle? =
        current_perceived_value(:approaching_obstacle, :is, about, rounds, false)

      %{is: not touched? and not approaching_obstacle?}
    end
  end

  defp obstacle_avoided_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      approaching_obstacle? =
        current_perceived_value(:approaching_obstacle, :is, about, rounds, false)

      distance_to_obstacle =
        current_perceived_value(:distance_to_obstacle, :is, about, rounds, :unknown)

      %{
        is:
          not approaching_obstacle? and (distance_to_obstacle == :unknown or distance_to_obstacle > 10)
      }
    end
  end

  # Intention valuators

  defp turn_valuator() do
    2 # seconds
  end

  defp move_valuator() do
    %{speed: :normal,
      time: 2}
  end

end
