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
      contradictions: [],
      priors: %{
        chewing: %{about: :self, values: %{is: false}},
        found_food: %{about: :self, values: %{is: false}}
      },
      intentions: %{
        chew: [
          %Intention{
            intent_name: :eat,
            valuator: chewing_valuator(),
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

  # opinion
  defp conjecture(:chewing) do
    %Conjecture{
      name: :chewing,
      activator: opinion_activator(:self),
      predictors: [
        no_change_predictor(:over_food, default: %{is: false})
      ],
      # always true if activated
      valuator: chewing_belief_valuator(),
      intention_domain: [:chew]
    }
  end

  # goal
  defp conjecture(:found_food) do
    %Conjecture{
      name: :found_food,
      activator: goal_activator(fn %{is: found_food?} -> found_food? end),
      predictors: [
        no_change_predictor(:over_food, default: %{is: false}),
        no_change_predictor(:approaching_food, default: %{is: false})
      ],
      valuator: found_food_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture belief valuators

  defp found_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      over_food? = current_perceived_value(round, about, :over_food, :is, default: false)

      %{is: over_food?}
    end
  end

  defp chewing_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      over_food? = current_perceived_value(round, about, :over_food, :is, default: false)

      %{is: over_food?}
    end
  end

  # Intention valuators

  defp chewing_valuator() do
    fn %{is: chewing?} = belief_values ->
      if chewing?, do: empty_valuator().(belief_values), else: nil
    end
  end

  defp chewing_noise() do
    fn %{is: chewing?} ->
      if chewing?, do: saying("Nom de nom de nom"), else: nil
    end
  end
end
