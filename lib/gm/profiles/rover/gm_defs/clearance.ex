defmodule Andy.GM.Profiles.Rover.GMDefs.Clearance do
  @moduledoc "The GM definition for :clearance"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Profiles.Rover.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :danger,
      conjectures: [
        conjecture(:clear_of_obstacle),
        conjecture(:clear_of_other)
      ],
      contradictions: [],
      priors: %{clear_of_obstacle: %{is: true},
                clear_of_other: %{is: true}},
      intentions: %{}
    }
  end

  # Conjectures

  defp conjecture(:clear_of_obstacle) do
    %Conjecture{
      name: :clear_of_obstacle,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor(:obstacle_not_hit, %{is: true}),
        no_change_predictor(:obstacle_avoided, %{is: true})
      ],
      valuator: clear_of_obstacle_valuator(),
      intention_domain: []
    }
  end

  defp conjecture(:clear_of_other) do
    %Conjecture{
      name: :clear_of_other,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor(:other_rover_out_of_range, %{is: true}),
        no_change_predictor(:other_rover_avoided, %{is: true})
      ],
      valuator: clear_of_other_valuator(),
      intention_domain: []
    }
  end


  # Conjecture activators

  # Conjecture predictors

  # Conjecture belief valuators

  defp clear_of_obstacle_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      obstacle_not_hit? =
        current_perceived_value(:obstacle_not_hit, :is, about, rounds, true)

      obstacle_avoided? = current_perceived_value(:obstacle_avoided, :is, about, rounds, true)

      %{is: obstacle_not_hit? and obstacle_avoided?}
    end
  end

  defp clear_of_other_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      other_rover_out_of_range? =
        current_perceived_value(:other_rover_out_of_range, :is, about, rounds, true)

      other_rover_avoided? = current_perceived_value(:other_rover_avoided, :is, about, rounds, true)

      %{is: other_rover_out_of_range? and other_rover_avoided?}
    end
  end


  # Intention valuators

 end
