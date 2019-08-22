defmodule Andy.GM.Profiles.Rover.GMDefs.Lighting do
  @moduledoc "The GM definition for :lighting"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utilss

  def gm_def() do
    %GenerativeModelDef{
      name: :ligting,
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
        no_change_predictor("*:*:ambient", %{detected: 100})
      ],
      valuator: in_well_lit_area_valuator(),
      intention_domain: [:express_feeling_about_safety] ++ movement_domain()
    }
  end

  # Conjecture activators

  defp in_well_lit_area_activator() do
    fn conjecture, [round, _previous_rounds] ->
      ambient_light = current_perceived_value("*:*:ambient", :detected, :self, round, 100)

      if ambient_light < 10 do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal?: true
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

      clear_of_obstacle? = current_perceived_value(:clear_of_obstacle, :is, about, round, true)

      clear_of_other? = current_perceived_value(:clear_of_other, :is, about, round, true)
      in_well_lit_area? = current_perceived_value(:in_well_lit_area, :is, about, round, true)

      %{is: clear_of_obstacle? and clear_of_other? and in_well_lit_area?}
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
