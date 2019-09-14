defmodule Andy.Profiles.Rover.GMDefs.ObstacleApproach do
  @moduledoc "The GM definition for :obstacle_approach"

  alias Andy.GM.{GenerativeModelDef, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :obstacle_approach,
      conjectures: [
        conjecture(:approaching_obstacle)
      ],
      contradictions: [],
      priors: %{
        approaching_obstacle: %{about: :self, values: %{is: false}}
      },
      intentions: %{}
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:approaching_obstacle) do
    %Conjecture{
      name: :approaching_obstacle,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor(:distance_to_obstacle, default: %{is: :unknown})
      ],
      valuator: approaching_obstacle_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture belief valuators

  defp approaching_obstacle_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      approaching? =
        numerical_perceived_value_trend(rounds, :distance_to_obstacle, about, :is) == :decreasing

      %{is: approaching?}
    end
  end
end
