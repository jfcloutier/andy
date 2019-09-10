defmodule Andy.Profiles.Rover.GMDefs.ObservingOther do
  @moduledoc "The GM definition for :observing_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :observing_other,
      conjectures: [
        conjecture(:not_seen),
        conjecture(:observed)
      ],
      contradictions: [[:not_seen, :observed]],
      priors: %{
        not_seen: %{about: :other, values: %{is: true}},
        observed: %{about: :other, values: %{is: false}}
      },
      intentions: %{
        face: %Intention{
          intent_name: :turn,
          valuator: face_valuator(),
          repeatable: true
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:not_seen) do
    %Conjecture{
      name: :not_seen,
      activator: always_activator(:opinion, :other),
      predictors: [
        no_change_predictor("*:*:direction_mod", default: %{detected: :unknown})
      ],
      valuator: not_seen_belief_valuator(),
      intention_domain: [],
      self_activated: true
    }
  end

  defp conjecture(:observed) do
    %Conjecture{
      name: :observed,
      activator: observed_activator(),
      predictors: [
        no_change_predictor("*:*:proximity_mod", default: %{detected: :unknown}),
        no_change_predictor("*:*:direction_mod", default: %{detected: :unknown})
      ],
      valuator: observed_belief_valuator(),
      intention_domain: [:face]
    }
  end

  # Conjecture activators

  defp observed_activator() do
    fn conjecture, rounds, _prediction_about ->
      recently_observed? =
        once_believed?(rounds, :other, :observed, :is, true, since: now() - 30_000)

      # if we have not observed the other in the last 30 secs
      if not recently_observed? do
        [
          Conjecture.activate(conjecture,
            about: :other,
            # face the other robot for 5 secs or give up after failing to for 10 secs
            goal: fn %{since: since, failing_since: failing_since} ->
              since >= 5_000 or failing_since > 10_000
            end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp not_seen_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      not_seen? =
        current_perceived_value(
          round,
          about,
          "*:*:direction_mod",
          :detected,
          default: :unknown
        ) == :unknown

      %{is: not_seen?}
    end
  end

  defp observed_belief_valuator() do
    fn conjecture_activation, [round | previous_rounds] ->
      about = conjecture_activation.about

      proximity =
        current_perceived_value(
          round,
          about,
          "*:*:proximity_mod",
          :detected,
          default: :unknown
        )

      direction =
        current_perceived_value(round, about, "*:*:direction_mod", :detected, default: :unknown)

      facing? = less_than?(absolute(direction), 60)

      since = duration_believed(previous_rounds, about, :observed, :is, true)
      failing_since = duration_believed(previous_rounds, about, :observed, :is, false)

      %{
        is: facing?,
        direction: direction,
        proximity: proximity,
        since: since,
        failing_since: failing_since
      }
    end
  end

  # Intention valuators

  defp face_valuator() do
    fn %{direction: :unknown} ->
      turn_direction = Enum.random([:right, :left])
      %{value: %{turn_direction: turn_direction, turn_time: 1}, duration: 1}
    end

    fn %{direction: direction} when abs(direction) <= 60 ->
      nil
    end

    fn %{direction: direction} ->
      turn_direction = if direction < 0, do: :left, else: :right
      %{value: %{turn_direction: turn_direction, turn_time: 0.5}, duration: 0.5}
    end
  end
end
