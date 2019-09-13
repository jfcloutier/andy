defmodule Andy.Profiles.Rover.GMDefs.SeekingFood do
  @moduledoc "The GM definition for :seeking_food"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :seeking_food,
      conjectures: [
        conjecture(:over_food),
        conjecture(:approaching_food)
      ],
      contradictions: [
        [:over_food, :approaching_food]
      ],
      priors: %{
        over_food: %{about: :self, values: %{is: false}},
        approaching_food: %{about: :self, values: %{is: false, got_it: false}}
      },
      intentions: %{
        express_opinion_about_food: %Intention{
          intent_name: :say,
          valuator: opinion_about_food(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:over_food) do
    %Conjecture{
      name: :over_food,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor("*:*:color", default: %{detected: :unknown})
      ],
      valuator: over_food_belief_valuator(),
      intention_domain: [:express_opinion_about_food]
    }
  end

  defp conjecture(:approaching_food) do
    %Conjecture{
      name: :other_found_food,
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

  defp approaching_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      over_food? = over_food?(round, prediction_about)

      if not over_food? do
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

  # Conjecture predictors

  # Conjecture belief valuators

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
    fn %{is: found_food?} ->
      if found_food?, do: saying("Food!"), else: nil
    end
  end

  #

  defp over_food?(round, about) do
    current_perceived_value(round, about, "*:*:color", :detected, default: :unknown) == :white
  end
end
