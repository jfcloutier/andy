defmodule Andy.Profiles.Rover.GMDefs.ObstacleDistance do
  @moduledoc "The GM definition for :obstacle_distance"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :obstacle_distance,
      conjectures: [
        conjecture(:distance_to_obstacle)
      ],
      contradictions: [],
      priors: %{distance_to_obstacle: %{about: :self, values: %{is: :unknown}}},
      intentions: %{
        express_opinion_about_distance: %Intention{
          intent_name: :say,
          valuator: opinion_about_distance(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:distance_to_obstacle) do
    %Conjecture{
      name: :distance_to_obstacle,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor("*:*:distance", default: %{detected: :unknown})
      ],
      valuator: distance_to_obstacle_valuator(),
      intention_domain: [:express_opinion_about_distance]
    }
  end

  # Conjecture activators

  # Conjecture predictors

  # Conjecture belief valuators

  defp distance_to_obstacle_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      distance = current_perceived_value(round, about, "*:*:distance", :detected, default: :unknown)

      %{is: distance}
    end
  end

  # Intention valuators

  defp opinion_about_distance() do
    fn %{is: distance} -> if less_than?(distance, 10), do: "Oops!", else: nil end
    fn _ -> nil end
  end
end
