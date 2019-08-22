defmodule Andy.GM.Profiles.Rover do
  @moduledoc "The cognition profile of a rover"

  alias Andy.GM.{Cognition}
  alias Andy.GM.Profiles.Rover.GMDefs.{Being, Danger, Hunger, Freedom, Clearance, Lighting, ObstacleApproach,
                                       AvoidingObstacle, ObstacleDistance, AvoidingOtherRover, OtherRoverProximity,
                                       CollisionCourseWithOtherRover, Eating, SeekingFood, BehaviorOfOtherRover,
                                       ObservingOtherRover}
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
        AvoidingOtherRover.gm_def(),
        OtherRoverProximity.gm_def(),
        CollisionCourseWithOtherRover.gm_def(),
        Eating.gm_def(),
        SeekingFood.gm_def(),
        BehaviorOfOtherRover.gm_def(),
        ObservingOtherRover.gm_def()
      ],
      children: %{
        being: [:danger, :hunger, :freedom],
        danger: [:clearance, :lighting, :behavior_of_other_rover],
        hunger: [:eating],
        freedom: [],
        clearance: [:avoiding_obstacle, :avoiding_other_rover],
        avoiding_obstacle: [:obstacle_approach, :obstacle_distance],
        obstacle_approach: [],
        obstacle_distance: [],
        avoiding_other_rover: [:other_rover_proximity, :collision_course_with_other_rover],
        other_rover_proximity: [],
        collision_course_with_other_rover: [:other_rover_proximity],
        lighting: [],
        eating: [:seeking_food],
        seeking_food: [:behavior_of_other_rover],
        behavior_of_other_rover: [:observing_other_rover],
        observing_other_rover: []
      }
    }
  end
end
