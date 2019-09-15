defmodule Andy.Profiles.Rover.GMDefs.SeekingFood do
  @moduledoc "The GM definition for :seeking_food"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :seeking_food,
      conjectures: [
        conjecture(:no_food),
        conjecture(:over_food),
        conjecture(:approaching_food)
      ],
      contradictions: [
        [:over_food, :approaching_food]
      ],
      priors: %{
        no_food: %{about: :self, values: %{is: false}},
        over_food: %{about: :self, values: %{is: false}},
        approaching_food: %{about: :self, values: %{is: false, got_it: false}}
      },
      intentions: %{
        express_opinion_about_food: %Intention{
          intent_name: :say,
          valuator: opinion_about_food(),
          repeatable: false
        },
        roam_about: %Intention{
          intent_name: :move,
          valuator: no_food_roam_valuator()
        }
      }
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:no_food) do
    %Conjecture{
      name: :no_food,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor("*:*:beacon_heading/1", default: %{detected: :unknown}),
        no_change_predictor("*:*:beacon_distance/1", default: %{detected: :unknown})
      ],
      valuator: no_food_belief_valuator(),
      intention_domain: [:roam_about]
    }
  end

  # opinion
  defp conjecture(:over_food) do
    %Conjecture{
      name: :over_food,
      activator: over_food_activator(),
      predictors: [
        no_change_predictor("*:*:color", default: %{detected: :unknown})
      ],
      valuator: over_food_belief_valuator(),
      intention_domain: [:express_opinion_about_food]
    }
  end

  defp conjecture(:approaching_food) do
    %Conjecture{
      name: :approaching_food,
      activator: approaching_food_activator(),
      predictors: [
        no_change_predictor(:closer_to_food, default: %{is: false}),
        no_change_predictor(:closer_to_other_homing, default: %{is: false})
      ],
      valuator: approaching_food_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture activators

  defp over_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      no_food_believed? = current_believed_value(round, prediction_about, :no_food, :is, default: false)

      if not no_food_believed? do
        [
          Conjecture.activate(conjecture,
            about: prediction_about
          )
        ]
      else
        []
      end
    end
  end

  defp approaching_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      over_food_believed? = current_believed_value(round, prediction_about, :over_food, :is, default: false)
      no_food_believed? = current_believed_value(round, prediction_about, :no_food, :is, default: false)

      if not (no_food_believed? or over_food_believed?) do
        [
          Conjecture.activate(conjecture,
            about: prediction_about,
            goal: fn %{got_it: got_it?} -> got_it? end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture belief valuators

  defp no_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      no_food? = no_food?(round, about)

      %{is: no_food?}
    end
  end

  defp over_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      over_food? = over_food?(round, about)

      %{is: over_food?}
    end
  end

  def approaching_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      closer_to_food? =
        current_perceived_value(round, about, :closer_to_food, :is, default: false)

      closer_to_other_homing? =
        current_perceived_value(round, about, :closer_to_other_homing, :is, default: false)

      got_it? = over_food?(round, about)

      %{
        is: closer_to_food? or closer_to_other_homing?,
        got_it: got_it?
      }
    end
  end

  # Intention valuators

  defp opinion_about_food() do
    fn %{is: over_food?} ->
      if over_food?, do: saying("Food!"), else: nil
    end
  end

  defp no_food_roam_valuator() do
    fn %{is: no_food?} = belief_values ->
      if no_food?, do: roam_valuator().(belief_values), else: nil
    end
  end


  #

  defp over_food?(round, about) do
    current_perceived_value(round, about, "*:*:color", :detected, default: :unknown) == :white
  end

  defp no_food?(round, about) do
    heading = current_perceived_value(round, about, "*:*:beacon_heading/1", :detected, default: :unknown)
    distance = current_perceived_value(round, about, "*:*:beacon_distance/1", :detected, default: :unknown)
    heading == :unknown or distance == :unknown
  end
end
