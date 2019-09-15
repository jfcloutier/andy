defmodule Andy.Profiles.Rover.GMDefs.FoodLocation do
  @moduledoc "The GM definition for :food_location"

  alias Andy.GM.{GenerativeModelDef, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :food_location,
      conjectures: [
        conjecture(:location_of_food)
      ],
      contradictions: [],
      priors: %{
        location_of_food: %{about: :self, values: %{distance: :unknown, heading: :unknown}}
      },
      intentions: %{}
    }
  end

  # Conjectures

  # Opinion
  defp conjecture(:location_of_food) do
    %Conjecture{
      name: :location_of_food,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor(
          "*:*:beacon_heading/1",
          :self,
          default: %{
            detected: :unknown
          }
        ),
        no_change_predictor(
          "*:*:beacon_distance/1",
          :self,
          default: %{
            detected: :unknown
          }
        )
      ],
      valuator: location_of_food_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture belief valuators

  defp location_of_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      heading_read =
        current_perceived_value(round, about, "*:*:beacon_heading/1", :detected, default: :unknown)

      distance_read =
        current_perceived_value(round, about, "*:*:beacon_distance/1", :detected,
          default: :unknown
        )

      distance = if distance_read == 70 and heading_read == 0, do: :unknown, else: distance_read
      heading = if distance_read == 70 and heading_read == 0, do: :unknown, else: heading_read
      %{distance: distance, heading: heading}
    end
  end

 end
