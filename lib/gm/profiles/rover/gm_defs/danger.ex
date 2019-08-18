defmodule Andy.GM.Profiles.Rover.GMDefs.Danger do
  @moduledoc "The GM definition for :danger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Profiles.Rover.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :danger,
      conjectures: [
        conjecture(:safe)
      ],
      contradictions: [],
      priors: %{safe: %{is: true}},
      intentions: %{
        express_opinion_about_safety: %Intention{
          intent_name: :say,
          valuator: opinion_about_safety(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:safe) do
    %Conjecture{
      name: :safe,
      activator: safe_activator(),
      predictors: [
        no_change_predictor(:clear_of_obstacle, %{is: true}),
        no_change_predictor(:clear_of_other, %{is: true}),
        no_change_predictor(:in_well_lit_area, %{is: true})
      ],
      valuator: safe_valuator(),
      intention_domain: [:express_opinion_about_safety]
    }
  end

  # Conjecture activators

  # Always activate, and as opinion
  defp safe_activator() do
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

  defp safe_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      clear_of_obstacle? =
        current_perceived_value(:clear_of_obstacle, :is, about, rounds, false)

      clear_of_other? = current_perceived_value(:clear_of_other, :is, about, rounds, false)
      in_well_lit_area? = current_perceived_value(:in_well_lit_area, :is, about, rounds, false)

      %{is: clear_of_obstacle? and clear_of_other? and in_well_lit_area?}
    end
  end

  # Intention valuators

  defp opinion_about_safety() do
    fn %{is: true} ->
      "I feel safe"
    end

    fn _other ->
      "Danger!"
    end
  end
end
