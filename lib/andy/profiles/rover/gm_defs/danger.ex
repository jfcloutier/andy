defmodule Andy.Profiles.Rover.GMDefs.Danger do
  @moduledoc "The GM definition for :danger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :danger,
      conjectures: [
        conjecture(:safe),
        conjecture(:panic),
        conjecture(:group_panic)
      ],
      contradictions: [],
      priors: %{
        safe: %{about: :self, values: %{is: true}},
        group_panic: %{about: :self, values: %{is: false, well_lit: true}},
        panic: %{about: :self, values: %{is: false, well_lit: true}}
      },
      intentions: %{
        express_opinion_about_safety: %Intention{
          intent_name: :say,
          valuator: opinion_about_safety(),
          repeatable: false
        },
        panicking: [
          %Intention{
            intent_name: :panic,
            valuator: panic_valuator(),
            duplicable: false
          },
          %Intention{
            intent_name: :say,
            valuator: opinion_about_panic(),
            repeatable: false
          }
        ]
      }
    }
  end

  # Conjectures

  # goals
  defp conjecture(:safe) do
    %Conjecture{
      name: :safe,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor(:clear_of_obstacle, default: %{is: true}),
        no_change_predictor(:clear_of_other, default: %{is: true})
      ],
      valuator: safe_belief_valuator(),
      intention_domain: [:express_opinion_about_safety]
    }
  end

  # opinion
  defp conjecture(:panic) do
    %Conjecture{
      name: :panic,
      activator: opinion_activator(:self),
      predictors: [
        no_change_predictor(:in_well_lit_area, default: %{is: true})
      ],
      valuator: panic_belief_valuator(),
      self_activated: true,
      intention_domain: [:panicking]
    }
  end

  # opinion
  defp conjecture(:group_panic) do
    %Conjecture{
      name: :group_panic,
      activator: opinion_activator(:self),
      predictors: [
        no_change_predictor(:in_well_lit_area, default: %{is: true}),
        no_change_predictor(:other_panicking, default: %{is: false})
      ],
      valuator: group_panic_belief_valuator(),
      self_activated: true,
      intention_domain: [:panicking]
    }
  end

  # Conjecture belief valuators

  defp safe_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      group_panic? =
        current_believed_value(
          round,
          about,
          :group_panic,
          :is,
          default: false
        )

      clear_of_obstacle? =
        current_perceived_value(round, about, :clear_of_obstacle, :is, default: true)

      clear_of_other? = current_perceived_value(round, about, :clear_of_other, :is, default: true)

      %{is: not group_panic? and clear_of_obstacle? and clear_of_other?}
    end
  end

  defp group_panic_belief_valuator() do
    fn conjecture_activation, [round | previous_rounds] ->
      about = conjecture_activation.about

      recent_group_panic? =
        once_believed?(previous_rounds, about, :group_panic, :is, true, since: now() - 20_000)

      other_panicking? =
        current_perceived_value(
          round,
          about,
          :other_panicking,
          :is,
          default: false
        )

      panicking? = not recent_group_panic? and other_panicking?

      in_well_lit_area? =
        current_perceived_value(round, :self, :in_well_lit_area, :is, default: true)

      %{is: panicking?, well_lit: in_well_lit_area?}
    end
  end

  defp panic_belief_valuator() do
    fn conjecture_activation, [round | previous_rounds] = rounds ->
      about = conjecture_activation.about
      now = now()

      recent_panic? =
        once_believed?(previous_rounds, about, :panic, :is, true, since: now - 20_000)

      unsafe_since = believed_since(rounds, about, :safe, :is, false)
      very_unsafe? = unsafe_since != nil and unsafe_since > now - 5_000
      panicking? = not recent_panic? and very_unsafe?

      in_well_lit_area? =
        current_perceived_value(round, :self, :in_well_lit_area, :is, default: true)

      %{is: panicking?, well_lit: in_well_lit_area?}
    end
  end

  # Intention valuators

  defp opinion_about_safety() do
    fn %{is: safe?} ->
      if safe?, do: saying("I feel safe"), else: saying("Danger!")
    end
  end

  defp opinion_about_panic() do
    fn %{is: panicking?} ->
      if panicking?, do: saying("Help! Help!"), else: nil
    end
  end

  defp panic_valuator() do
    fn %{is: panicking?, well_lit: well_lit?} ->
      if panicking? do
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
      else
        nil
      end
    end
  end
end
