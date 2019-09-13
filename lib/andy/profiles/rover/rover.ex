defmodule Andy.Profiles.Rover do
  @moduledoc "The cognition profile of a rover"

  alias Andy.GM.{Cognition}

  alias Andy.Profiles.Rover.GMDefs.{
    Being,
    Danger,
    Hunger,
    Freedom,
    Clearance,
    Lighting,
    ObstacleApproach,
    AvoidingObstacle,
    ObstacleDistance,
    CollisionCourseWithOther,
    Eating,
    SeekingFood,
    FoodApproach,
    IntentionsOfOther,
    ObservingOther
  }

  #

  def cognition() do
    %Cognition{
      gm_defs: [
        Being.gm_def(),
        Danger.gm_def(),
        Hunger.gm_def(),
        Freedom.gm_def(),
        Clearance.gm_def(),
        Lighting.gm_def(),
        AvoidingObstacle.gm_def(),
        ObstacleDistance.gm_def(),
        ObstacleApproach.gm_def(),
        CollisionCourseWithOther.gm_def(),
        Eating.gm_def(),
        SeekingFood.gm_def(),
        FoodApproach.gm_def(),
        IntentionsOfOther.gm_def(),
        ObservingOther.gm_def()
      ],
      children: %{
        being: [:danger, :hunger, :freedom],
        danger: [:clearance, :lighting, :intentions_of_other],
        hunger: [:eating],
        freedom: [],
        clearance: [:avoiding_obstacle, :collision_course_with_other],
        avoiding_obstacle: [:obstacle_approach, :obstacle_distance],
        obstacle_approach: [],
        obstacle_distance: [],
        collision_course_with_other: [],
        lighting: [],
        eating: [:seeking_food],
        seeking_food: [:food_approach],
        food_approach: [:intentions_of_other],
        intentions_of_other: [:observing_other],
        observing_other: []
      }
    }
  end
end
