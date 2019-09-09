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

  defp conjecture(:obstacle_not_hit) do
    %Conjecture{
      name: :obstacle_not_hit,
      activator: obstacle_not_hit_activator(),
      predictors: [
        no_change_predictor(:distance_to_obstacle, default: %{detected: :unknown})
      ],
      valuator: obstacle_not_hit_valuator(),
      intention_domain: movement_domain()
    }
  end

  defp conjecture(:obstacle_avoided) do
    %Conjecture{
      name: :obstacle_avoided,
      activator: always_activator(:goal),
      predictors: [
        distance_to_obstacle_predictor()
      ],
      valuator: obstacle_avoided_valuator(),
      intention_domain: movement_domain()
    }
  end

  # Conjecture activators

  defp obstacle_not_hit_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      touched? = touched?(round, prediction_about)

      if touched? do
        [
          Conjecture.activate(conjecture,
            about: prediction_about,
            goal: fn %{is: not_hit?} -> not_hit? == true end
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
        expectations: Map.new([{:is, expectation}])
      }
    end
  end

  # Conjecture belief valuators

  defp obstacle_not_hit_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      touched? = touched?(round, about)

      approaching_obstacle? =
        current_perceived_value(round, about, :approaching_obstacle, :is, default: false)

      %{is: not touched? and not approaching_obstacle?}
    end
  end

  defp obstacle_avoided_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      approaching_obstacle? =
        current_perceived_value(round, about, :approaching_obstacle, :is, default: false)

      distance_to_obstacle =
        current_perceived_value(round, about, :distance_to_obstacle, :is, default: :unknown)

      %{
        is:
          not approaching_obstacle? and greater_than?(distance_to_obstacle, 10)
      }
    end
  end

  # Intention valuators

  #
  defp touched?(round, prediction_about) do
    current_perceived_value(round, prediction_about, :distance_to_obstacle, :is, default: :unknown) |> less_than?(5)
  end

end
