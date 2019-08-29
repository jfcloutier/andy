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
      priors: %{in_well_lit_area: %{is: true}},
      intentions:
        %{
          express_feeling_about_light: %Intention{
            intent_name: :say,
            valuator: feeling_about_light(),
            repeatable: false
          }
        }
        |> Map.merge(movement_intentions())
    }
  end

  # Conjectures

  defp conjecture(:in_well_lit_area) do
    %Conjecture{
      name: :safe,
      activator: in_well_lit_area_activator(),
      predictors: [
        no_change_predictor("*:*:ambient", default: %{detected: 100})
      ],
      valuator: in_well_lit_area_valuator(),
      intention_domain: [:express_feeling_about_safety] ++ movement_domain()
    }
  end

  # Conjecture activators

  defp in_well_lit_area_activator() do
    fn conjecture, [round, _previous_rounds] ->
      ambient_light =
        current_perceived_value(round, :self, "*:*:ambient", :detected, default: 100)

      if ambient_light < 10 do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal: fn %{is: well_lit?} -> well_lit? end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp in_well_lit_area_valuator() do
    fn conjecture_activation, [round, _previous_rounds] ->
      about = conjecture_activation.about

      in_well_lit_area? =
        current_perceived_value(round, about, "*:*:ambient", :detected, default: 100) >= 10

      %{is: in_well_lit_area?}
    end
  end

  # Intention valuators

  defp feeling_about_light() do
    fn %{is: true} ->
      "Now I can see"
    end

    fn _other ->
      "It's too dark!"
    end
  end
end
