defmodule Andy.GM.Profiles.Rover.GMDefs.Hunger do
  @moduledoc "The GM definition for :hunger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Profiles.Rover.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :hunger,
      conjectures: [
        conjecture(:sated)
      ],
      contradictions: [],
      priors: %{sated: %{is: true}},
      intentions: %{
        express_opinion_about_hunger: %Intention{
          intent_name: :say,
          valuator: opinion_about_hunger(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:sated) do
    %Conjecture{
      name: :sated,
      activator: sated_activator(),
      predictors: [
        no_change_predictor(:belly_full, %{is: true})
      ],
      valuator: sated_valuator(),
      intention_domain: [:express_opinion_about_hunger]
    }
  end

  # Conjecture activators

  # Always activate, and as opinion
  defp sated_activator() do
    fn conjecture, _rounds ->
      [
        Conjecture.activate(conjecture,
          about: :self,
          goal?: false
        )
      ]
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp sated_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      belly_full? = current_perceived_value(:belly_full, :is, about, rounds, false)

      %{is: belly_full?}
    end
  end

  # Intention valuators

  defp opinion_about_hunger() do
    fn %{is: true} ->
      "I am hungry"
    end

    fn _other ->
      "I am not hungry"
    end
  end
end
