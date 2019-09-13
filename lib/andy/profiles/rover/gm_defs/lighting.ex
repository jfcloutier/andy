defmodule Andy.Profiles.Rover.GMDefs.Lighting do
  @moduledoc "The GM definition for :lighting"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :lighting,
      conjectures: [
        conjecture(:in_well_lit_area)
      ],
      contradictions: [],
      priors: %{in_well_lit_area: %{about: :self, values: %{is: true}}},
      intentions: %{
        express_feeling_about_light: %Intention{
          intent_name: :say,
          valuator: feeling_about_light(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:in_well_lit_area) do
    %Conjecture{
      name: :in_well_lit_area,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor("*:*:ambient", default: %{detected: 100})
      ],
      valuator: in_well_lit_area_belief_valuator(),
      intention_domain: [:express_feeling_about_safety]
    }
  end

  # Conjecture belief valuators

  defp in_well_lit_area_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      in_well_lit_area? =
        current_perceived_value(round, about, "*:*:ambient", :detected, default: 100)
        |> greater_than?(10)

      %{is: in_well_lit_area?}
    end
  end

  # Intention valuators

  defp feeling_about_light() do
    fn %{is: true} ->
      saying("Now I can see")
    end

    fn _other ->
      saying("It's too dark!")
    end
  end
end
