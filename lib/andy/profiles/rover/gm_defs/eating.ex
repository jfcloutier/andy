defmodule Andy.Profiles.Rover.GMDefs.Eating do
  @moduledoc "The GM definition for :eating"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :eating,
      conjectures: [
        conjecture(:chewing),
        conjecture(:found_food)
      ],
      contradictions: [[:chewing, :found_food]],
      priors: %{chewing: %{is: false}, found_food: %{is: false}},
      intentions: %{
        declare_looking_for_food: %Intention{
          intent_name: :say,
          valuator: looking_for_food_declaration(),
          repeatable: false
        },
        chew: [
          %Intention{
            intent_name: :eat,
            valuator: empty_valuator(),
            repeatable: true
          },
          %Intention{
            intent_name: :say,
            valuator: chewing_noise(),
            repeatable: true
          }
        ]
      }
    }
  end

  # Conjectures

  defp conjecture(:chewing) do
    %Conjecture{
      name: :chewing,
      activator: chewing_activator(),
      predictors: [
        no_change_predictor(:chewing, default: %{is: false})
      ],
      # always true if activated
      valuator: constant_valuator(%{is: true}),
      intention_domain: [:chew]
    }
  end

  defp conjecture(:found_food) do
    %Conjecture{
      name: :found_food,
      activator: always_activator(:goal),
      predictors: [
        no_change_predictor(:over_food, default: %{is: false}),
        no_change_predictor(:other_found_food, default: %{is: false})
      ],
      valuator: found_food_belief_valuator(),
      intention_domain: [:declare_looking_for_food]
    }
  end

  # Conjecture activators

  defp chewing_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      over_food? =
        current_perceived_value(round, prediction_about, :over_food, :is, default: false)

      if over_food? do
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

  # Conjecture predictors

  # Conjecture belief valuators

  defp found_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      over_food? = current_perceived_value(round, about, :over_food, :is, default: false)

      %{is: over_food?}
    end
  end

  # Intention valuators

  defp chewing_noise() do
    fn %{is: true} ->
      "Nom de nom de nom"
    end

    fn _other ->
      nil
    end
  end

  defp looking_for_food_declaration() do
    fn %{is: false} ->
      "I am looking for food"
    end

    fn _other ->
      nil
    end
  end
end
