defmodule Andy.Profiles.Rover.GMDefs.ObservingOther do
  @moduledoc "The GM definition for :observing_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, ConjectureActivation}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :observing_other,
      min_round_duration: 1_000,
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
            duration: 0,
            recently_believed_or_tried?: false
          }
        }
      },
      intentions: %{
        face: [
          %Intention{
            intent_name: :turn,
            valuator: face_turning_valuator(),
            repeatable: true
          },
          %Intention{
            intent_name: :say,
            valuator: face_saying_valuator(),
            repeatable: false
          }
        ]
      }
    }
  end

  # Conjectures

  # goal
  defp conjecture(:observed) do
    %Conjecture{
      name: :observed,
      activator:
        goal_activator(
          # until observing the other succeeded or failed for at least 5 consecutive seconds
          fn %{duration: duration} -> duration >= 5_000 end,
          :other
        ),
      predictors: [
        no_change_predictor("*:*:proximity_mod", default: %{detected: :unknown}),
        no_change_predictor("*:*:direction_mod", default: %{detected: :unknown})
      ],
      valuator: observed_belief_valuator(),
      intention_domain: [:face]
    }
  end

  # Conjecture belief valuators

  defp observed_belief_valuator() do
    fn conjecture_activation, [_round | previous_rounds] = rounds ->
      about = conjecture_activation.about
      conjecture_name = ConjectureActivation.conjecture_name(conjecture_activation)

      proximity =
        latest_perceived_value(
          rounds,
          about,
          "*:*:proximity_mod",
          :detected,
          default: :unknown
        )

      direction =
        latest_perceived_value(rounds, about, "*:*:direction_mod", :detected, default: :unknown)

      facing? = less_than?(absolute(direction), 181)
      now = now()

      duration =
        case believed_since(previous_rounds, about, :observed, :is, facing?) do
          nil ->
            0

          since ->
            now - since
        end

      recently_observed_or_tried? =
        recent_believed_values(rounds, about, conjecture_name, matching: %{}, since: now - 10_000)
        |> Enum.any?(&(&1.duration >= 5_000))

      %{
        is: facing?,
        direction: direction,
        proximity: proximity,
        duration: duration,
        recently_observed_or_tried: recently_observed_or_tried?
      }
    end
  end

  # Intention valuators

  defp face_turning_valuator() do
    fn %{direction: direction, recently_observed_or_tried: recently_observed_or_tried?} ->
      cond do
        # don't bother if in the last 20 secs we observed the other, or failed to, for at least 5 consecutive secs
        recently_observed_or_tried? ->
          nil

        direction == :unknown ->
          turn_direction = Enum.random([:right, :left])
          %{value: %{turn_direction: turn_direction, turn_time: 1}, duration: 1}

        abs(direction) < 181 ->
          nil

        true ->
          turn_direction = if direction < 0, do: :left, else: :right
          %{value: %{turn_direction: turn_direction, turn_time: 0.5}, duration: 0.5}
      end
    end
  end

  defp face_saying_valuator() do
    fn %{direction: direction, recently_observed_or_tried: recently_observed_or_tried?} ->
      name_of_other = Andy.name_of_other()

      cond do
        name_of_other == nil ->
          nil

        # don't bother if in the last 20 secs we observed the other, or failed to, for at least 5 consecutive secs
        recently_observed_or_tried? ->
          nil

        direction == :unknown ->
          saying(" #{name_of_other}, where are you?")

        abs(direction) < 181 ->
          saying("I'm watching you, #{name_of_other}")

        true ->
          saying("There you are, #{name_of_other}")
      end
    end
  end
end
