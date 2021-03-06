defmodule Andy.Profiles.Rover.GMDefs.Clearance do
  @moduledoc "The GM definition for :clearance"

  alias Andy.GM.{GenerativeModelDef, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :clearance,
      conjectures: [
        conjecture(:clear_of_obstacle),
        conjecture(:clear_of_other)
      ],
      contradictions: [],
      priors: %{
        clear_of_obstacle: %{about: :self, values: %{is: true}},
        clear_of_other: %{about: :self, values: %{is: true}}
      },
      intentions: %{}
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:clear_of_obstacle) do
    %Conjecture{
      name: :clear_of_obstacle,
      activator: opinion_activator(),
      predictors: [
        no_change_predictor(:obstacle_not_hit, default: %{is: true}),
        no_change_predictor(:obstacle_avoided, default: %{is: true})
      ],
      valuator: clear_of_obstacle_belief_valuator(),
      intention_domain: []
    }
  end

  # opinion
  defp conjecture(:clear_of_other) do
    %Conjecture{
      name: :clear_of_other,
      activator: opinion_activator(:other),
      predictors: [
        no_change_predictor(:on_collision_course, default: %{is: false})
      ],
      valuator: clear_of_other_belief_valuator(),
      intention_domain: []
    }
  end

  # Conjecture belief valuators

  defp clear_of_obstacle_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      obstacle_not_hit? =
        current_perceived_value(round, about, :obstacle_not_hit, :is, default: true)

      obstacle_avoided? =
        current_perceived_value(round, about, :obstacle_avoided, :is, default: true)

      %{is: obstacle_not_hit? and obstacle_avoided?}
    end
  end

  defp clear_of_other_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      on_collision_course? =
        current_perceived_value(round, about, :on_collision_course, :is, default: false)

      %{is: not on_collision_course?}
    end
  end
end
