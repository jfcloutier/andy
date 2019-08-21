defmodule Andy.GM.Profiles.Rover.GMDefs.ObstacleApproach do
  @moduledoc "The GM definition for :obstacle_approach"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :obstacle_approach,
      conjectures: [
        conjecture(:approaching_obstacle)
      ],
      contradictions: [],
      priors: %{obstacle_not_hit: %{is: true}, obstacle_avoided: %{is: true}},
      intentions: %{}
    }
  end

  # Conjectures

  defp conjecture(:approaching_obstacle) do
    %Conjecture{
      name: :approaching_obstacle,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor(:distance_to_obstacle, default: %{is: :unknown})
      ],
      valuator: approaching_obstacle_valuator(),
      intention_domain: []
    }
  end

  # Conjecture activators


  # Conjecture predictors

  # Conjecture belief valuators

  defp approaching_obstacle_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

       approaching? = numerical_value_trend(rounds, :distance_to_obstacle, about, :is) == :decreasing
      %{is: approaching?}
    end
  end


  # Intention valuators

 end
