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
      priors: %{sated: %{about: :self, values: %{is: false}}},
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
      activator: goal_activator(fn %{is: sated?} -> sated? end),
      predictors: [
        no_change_predictor(:chewing, default: %{is: false}),
        no_change_predictor(:found_food, default: %{is: false})
      ],
      valuator: sated_belief_valuator(),
      intention_domain: [:express_opinion_about_sated]
    }
  end

  # Conjecture belief valuators

  defp sated_belief_valuator() do
    fn _conjecture_activation, rounds ->

      eat_count =
        count_intents_since(rounds, :eat, since: now() - 20_000)

      %{is: eat_count > 2}
    end
  end

  # Intention valuators

  defp opinion_about_sated() do
    fn %{is: sated?} ->
      if sated?, do: saying("I am full"), else: saying("I am hungry")
    end
  end
end
