defmodule Andy.Profiles.Rover.GMDefs.Danger do
  @moduledoc "The GM definition for :danger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :danger,
      conjectures: [
        conjecture(:safe)
      ],
      contradictions: [[:safe, :group_panic]],
      priors: %{
        safe: %{about: :self, values: %{is: true}},
        group_panic: %{about: :self, values: %{is: false}}
      },
      intentions: %{
        express_opinion_about_safety: %Intention{
          intent_name: :say,
          valuator: opinion_about_safety(),
          repeatable: false
        },
        panicking: %Intention{
          intent_name: :panic,
          valuator: panic_valuator(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  # goals
  defp conjecture(:safe) do
    %Conjecture{
      name: :safe,
      activator: safe_activator(),
      predictors: [
        no_change_predictor(:clear_of_obstacle, default: %{is: true}),
        no_change_predictor(:clear_of_other, default: %{is: true}),
        no_change_predictor(:other_panicking, :other, default: %{is: false})
      ],
      valuator: safe_belief_valuator(),
      intention_domain: [:express_opinion_about_safety]
    }
  end

  # opinion
  defp conjecture(:group_panic) do
    %Conjecture{
      name: :group_panic,
      activator: group_panic_activator(),
      predictors: [
        no_change_predictor(:in_well_lit_area, default: %{is: true}),
        no_change_predictor(:other_panicking, default: %{is: false})
      ],
      valuator: group_panic_belief_valuator(),
      intention_domain: [:panicking]
    }
  end

  # Conjecture activators

  defp safe_activator() do
    fn conjecture, [round | _previous_rounds], _prediction_about ->
      other_panicking? =
        current_perceived_value(
          round,
          :other,
          :other_panicking,
          :is,
          default: false
        )

      if not other_panicking? do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal: fn %{is: safe?} -> safe? end
          )
        ]
      else
        []
      end
    end
  end

  defp group_panic_activator() do
    fn conjecture, [round | _previous_rounds], _prediction_about ->
      other_panicking? =
        current_perceived_value(
          round,
          :other,
          :other_panicking,
          :is,
          default: true
        )

      if other_panicking? do
        [
          Conjecture.activate(conjecture,
            about: :self
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture belief valuators

  defp safe_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      clear_of_obstacle? =
        current_perceived_value(round, about, :clear_of_obstacle, :is, default: true)

      clear_of_other? = current_perceived_value(round, about, :clear_of_other, :is, default: true)

      %{is: clear_of_obstacle? and clear_of_other?}
    end
  end

  defp group_panic_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      other_panicking? =
        current_perceived_value(
          round,
          about,
          :other_panicking,
          :is,
          default: false
        )

      in_well_lit_area? =
        current_perceived_value(round, :self, :in_well_lit_area, :is, default: true)

      %{is: other_panicking?, well_lit: in_well_lit_area?}
    end
  end

  # Intention valuators

  defp opinion_about_safety() do
    fn %{is: true} ->
      saying("I feel safe")
    end

    fn _other ->
      saying("Danger!")
    end
  end

  defp panic_valuator() do
    fn %{is: true, well_lit: well_lit?} ->
      fear_factor = if well_lit?, do: :low, else: :high

      {back_off_speed, back_off_time, turn_time, repeats} =
        case fear_factor do
          :low ->
            {:fast, 1, 1, 1}

          :high ->
            {:very_fast, 2, 2, 2}
        end

      duration = (back_off_time + turn_time) * repeats

      %{
        value: %{
          back_off_speed: back_off_speed,
          back_off_time: back_off_time,
          turn_time: turn_time,
          repeats: repeats
        },
        duration: duration
      }
    end

    fn _other ->
      nil
    end
  end
end
