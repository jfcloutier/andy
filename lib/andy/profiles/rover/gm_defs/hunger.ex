defmodule Andy.Profiles.Rover.GMDefs.Hunger do
  @moduledoc "The GM definition for :hunger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :hunger,
      conjectures: [
        conjecture(:sated)
      ],
      contradictions: [],
      priors: %{sated: %{about: :self, values: %{is: true}}},
      intentions: %{
        express_opinion_about_sated: %Intention{
          intent_name: :say,
          valuator: opinion_about_sated(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  # goal
  defp conjecture(:sated) do
    %Conjecture{
      name: :sated,
      activator: sated_activator(),
      predictors: [
        no_change_predictor(:chewing, default: %{is: false}),
        no_change_predictor(:found_food, default: %{is: false})
      ],
      valuator: sated_belief_valuator(),
      intention_domain: [:express_opinion_about_sated]
    }
  end

  # Conjecture activators

  defp sated_activator() do
    fn conjecture, rounds, prediction_about ->
      if once_believed?(rounds, prediction_about, :sated, :is, true, since: now() - 20_000) do
        []
      else
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal: goal_activator(fn %{is: sated?} -> sated? end)
          )
        ]
      end
    end
  end

  # Conjecture belief valuators

  defp sated_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      chewings_count =
        count_perceived_since(rounds, about, :chewing, %{is: true}, since: now() - 20_000)

      %{is: chewings_count >= 3}
    end
  end

  # Intention valuators

  defp opinion_about_sated() do
    fn %{is: false} ->
      saying("I am hungry")
    end

    fn _other ->
      nil
    end
  end
end
