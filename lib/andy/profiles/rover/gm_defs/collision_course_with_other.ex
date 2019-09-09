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
      priors: %{on_collision_course: %{about: :other, values: %{is: false}}},
      intentions: %{}
    }
  end

  # Conjectures

  defp conjecture(:on_collision_course) do
    %Conjecture{
      name: :on_collision_course,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor("*:*:direction_mod}", default: %{is: :unknown}),
        no_change_predictor("*:*:proximity_mod}", default: %{is: :unknown})
      ],
      valuator: on_collision_course_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture activators

  # Conjecture predictors

  # Conjecture belief valuators

  defp on_collision_course_belief_valuator() do
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

      bee_line? =
        case perceived_value_range(
               previous_rounds,
               about,
               "*:*:direction_mod",
               :detected,
               since: now() - 10_000
             ) do
          nil ->
            false

          [min_direction..max_direction] ->
            min_direction == max_direction # in same 30 degrees range
        end

      close? = greater_than?(proximity, 7) # closest == 9
      %{is: close? and bee_line?}
    end
  end

  # Intention valuators
end
