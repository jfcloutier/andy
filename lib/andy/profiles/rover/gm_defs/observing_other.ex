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
      priors: %{not_seen: %{is: true}, observed: %{is: false}},
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
        no_change_predictor("*:*:distance/#{channel_of_other()}", default: %{detected: -128})
      ],
      valuator: not_seen_belief_valuator(),
      intention_domain: []
    }
  end

  defp conjecture(:observed) do
    %Conjecture{
      name: :observed,
      activator: observed_activator(),
      predictors: [
        no_change_predictor("*:*:distance/#{channel_of_other()}", default: %{detected: -128}),
        no_change_predictor("*:*:heading/#{channel_of_other()}", default: %{detected: 0})
      ],
      valuator: observed_belief_valuator(),
      intention_domain: [:face]
    }
  end

  # Conjecture activators

  defp observed_activator() do
    fn conjecture, rounds ->
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
    fn conjecture_activation, [round, _previous_rounds] ->
      about = conjecture_activation.about

      not_seen? =
        current_perceived_value(round, about, "*:*:distance/#{channel_of_other()}", :detected,
          default: -128
        ) == -128

      %{is: not_seen?}
    end
  end

  defp observed_belief_valuator() do
    fn conjecture_activation, [round, previous_rounds] ->
      about = conjecture_activation.about

      distance =
        current_perceived_value(round, about, "*:*:distance/#{channel_of_other()}", :detected,
          default: -128
        )

      target_heading =
        current_perceived_value(round, about, "*:*:heading/#{channel_of_other()}", :detected,
          default: 0
        )

      seen? = distance != -128
      facing? = abs(target_heading) < 15

      since = duration_believed_since(previous_rounds, about, :observed, :is, true)
      failing_since = duration_believed_since(previous_rounds, about, :observed, :is, false)

      %{
        is: seen? and facing?,
        heading: target_heading,
        distance: distance,
        since: since,
        failing_since: failing_since
      }
    end
  end

  # Intention valuators

  defp face_valuator() do
    fn %{distance: -128} ->
      turn_direction = Enum.random([:right, :left])
      %{turn_direction: turn_direction, turn_time: 1}
    end

    fn %{heading: 0} ->
      nil
    end

    fn %{heading: heading} ->
      if abs(heading < 10) do
        nil
      else
        turn_direction = if heading < 0, do: :left, else: :right
        %{turn_direction: turn_direction, turn_time: 0.5}
      end
    end
  end
end
