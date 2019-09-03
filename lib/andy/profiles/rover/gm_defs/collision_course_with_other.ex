defmodule Andy.Profiles.Rover.GMDefs.CollisionCourseWithOther do
  @moduledoc "The GM definition for :collision_course_with_other"

  alias Andy.GM.{GenerativeModelDef, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :collision_course_with_other,
      conjectures: [
        conjecture(:on_collision_course)
      ],
      contradictions: [],
      priors: %{on_collision_course: %{is: false}},
      intentions: %{}
    }
  end

  # Conjectures

  defp conjecture(:on_collision_course) do
    %Conjecture{
      name: :on_collision_course,
      activator: on_collision_course_activator(),
      predictors: [
        no_change_predictor("*:*:direction}", default: %{is: :unknown}),
        no_change_predictor("*:*:proximity}", default: %{is: :unknown})
      ],
      valuator: on_collision_course_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture activators

  defp on_collision_course_activator() do
    fn conjecture, [round | _previous_rounds], _prediction_about ->
      proximity =
        current_perceived_value(
          round,
          :other,
          "*:*:proximity",
          :detected,
          default: :unknown
        )

      if proximity != :unknown and proximity < 3 do
        [
          Conjecture.activate(conjecture,
            about: :other
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp on_collision_course_belief_valuator() do
    fn conjecture_activation, [round | previous_rounds] ->
      about = conjecture_activation.about

      proximity =
        current_perceived_value(
          round,
          :other,
          "*:*:proximity",
          :detected,
          default: :unknown
        )

      bee_line? =
        case perceived_value_range(
               previous_rounds,
               about,
               "*:*:direction",
               :detected,
               since: now() - 10_000
             ) do
          nil ->
            false

          [min_direction..max_direction] ->
            (max_direction - min_direction) < 2
        end

      close? = proximity != :unknown or proximity > 7
      %{is: close? and bee_line?}
    end
  end

  # Intention valuators
end
