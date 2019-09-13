defmodule Andy.Profiles.Rover.GMDefs.ObservingOther do
  @moduledoc "The GM definition for :observing_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :observing_other,
      conjectures: [
        conjecture(:observed)
      ],
      contradictions: [],
      priors: %{
        observed: %{
          about: :other,
          values: %{
            is: false,
            direction: :unknown,
            proximity: :unknown,
            since: 0,
            failing_since: 0
          }
        }
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

  # goal
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
        once_believed?(rounds, :other, :observed, :is, true, since: now() - 10_000)

      # if we have not observed the other in the last 10 secs
      if not recently_observed? do
        [
          Conjecture.activate(conjecture,
            about: :other,
            # face the other robot for 5 secs or give up after failing to for 5 secs
            goal: fn %{is: observed?, since: since, failing_since: failing_since} ->
              (observed? and since >= 5_000) or failing_since >= 5_000
            end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture belief valuators

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

      facing? = less_than?(absolute(direction), 120)
      now = now()
      observing_since = now - duration_believed(previous_rounds, about, :observed, :is, true)
      failing_since = now - duration_believed(previous_rounds, about, :observed, :is, false)

      %{
        is: facing?,
        direction: direction,
        proximity: proximity,
        since: observing_since,
        failing_since: failing_since
      }
    end
  end

  # Intention valuators

  defp face_valuator() do
    fn %{direction: direction} ->
      cond do
        direction == :unknown ->
          turn_direction = Enum.random([:right, :left])
          %{value: %{turn_direction: turn_direction, turn_time: 1}, duration: 1}

        abs(direction) <= 120 ->
          nil

        true ->
          turn_direction = if direction < 0, do: :left, else: :right
          %{value: %{turn_direction: turn_direction, turn_time: 0.5}, duration: 0.5}
      end
    end
  end
end
