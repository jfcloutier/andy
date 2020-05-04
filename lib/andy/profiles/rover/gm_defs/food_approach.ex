defmodule Andy.Profiles.Rover.GMDefs.FoodApproach do
  @moduledoc "The GM definition for :food_approach"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :food_approach,
      conjectures: [
        conjecture(:closer_to_food),
        conjecture(:closer_to_other_homing)
      ],
      contradictions: [],
      priors: %{
        closer_to_food: %{
          about: :self,
          values: %{is: false, distance: :unknown, heading: :unknown}
        },
        closer_to_other: %{
          about: :other,
          values: %{is: false, proximity: :unknown, direction: :unknown, food_detected: true}
        }
      },
      intentions: %{
        track_other: [
          %Intention{
            intent_name: :turn,
            valuator: turn_other_valuator(),
            duplicable: false
          },
          %Intention{
            intent_name: :wait,
            valuator: wait_track_other_valuator(),
            duplicable: false
          },
          %Intention{
            intent_name: :go_forward,
            valuator: go_forward_other_valuator(),
            duplicable: false
          }
        ],
        track_food: [
          %Intention{
            intent_name: :turn,
            valuator: turn_food_valuator(),
            duplicable: false
          },
          %Intention{
            intent_name: :wait,
            valuator: wait_track_food_valuator(),
            duplicable: false
          },
          %Intention{
            intent_name: :go_forward,
            valuator: go_forward_food_valuator(),
            duplicable: false
          }
        ]
      }
    }
  end

  # Conjectures

  # goal
  defp conjecture(:closer_to_food) do
    %Conjecture{
      name: :closer_to_food,
      activator: goal_activator(fn %{is: closer_to_food?} -> closer_to_food? end),
      predictors: [
        no_change_predictor(:location_of_food, :self,
          default: %{distance: :unknown, heading: :unknown}
        )
      ],
      valuator: closer_to_food_belief_valuator(),
      intention_domain: [:track_food]
    }
  end

  # goal
  defp conjecture(:closer_to_other_homing) do
    %Conjecture{
      name: :closer_to_other_homing,
      activator:
        goal_activator(fn %{is: closer_to_other_homing?} -> closer_to_other_homing? end, :other),
      predictors: [
        no_change_predictor(:other_homing_on_food,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )
      ],
      valuator: closer_to_other_homing_belief_valuator(),
      intention_domain: [:track_other]
    }
  end

  # Conjecture belief valuators

  defp closer_to_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] = rounds ->
      about = conjecture_activation.about

      %{distance: distance, heading: heading} =
        current_perceived_values(round, about, :location_of_food,
          default: %{distance: :unknown, heading: :unknown}
        )

      approaching? =
        not (distance == :unknown or (distance == 70 and heading == 0)) and
          numerical_perceived_value_trend(rounds, :location_of_food, about, :distance) ==
            :decreasing

      %{is: approaching?, distance: distance, heading: heading}
    end
  end

  def closer_to_other_homing_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] = rounds ->
      food_detected? = food_detected?(round, conjecture_activation.about)

      approaching? =
        numerical_perceived_value_trend(rounds, :other_homing_on_food, :other, :proximity) ==
          :decreasing

      other_vector =
        current_perceived_values(round, :other, :other_homing_on_food,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )

      %{
        is: approaching?,
        food_detected: food_detected?,
        proximity: other_vector.proximity,
        direction: other_vector.direction
      }
    end
  end

  # Intention valuators

  defp turn_food_valuator() do
    fn %{heading: heading} ->
      # suspicious!
      if heading == :unknown do
        nil
      else
        turn_direction = if heading < 0, do: :left, else: :right
        abs_heading = abs(heading)

        turn_time =
          cond do
            abs_heading <= 4 -> 0
            abs_heading < 10 -> 0.25
            abs_heading < 20 -> 0.5
            abs_heading < 30 -> 1
            true -> 1.5
          end

        %{
          value: %{
            turn_direction: turn_direction,
            turn_time: turn_time
          },
          duration: turn_time
        }
      end
    end
  end

  defp wait_track_food_valuator() do
    fn %{heading: heading, distance: distance} ->
      time = if distance == :unknown or heading == :unknown, do: 0, else: 0.5
      %{value: %{time: time}, duration: time}
    end
  end

  defp go_forward_food_valuator() do
    fn %{distance: distance} ->
      # suspicious!
      if distance == :unknown do
        nil
      else
        speed =
          cond do
            distance < 10 -> :very_slow
            distance < 15 -> :slow
            distance < 30 -> :normal
            true -> :fast
          end

        forward_time =
          cond do
            distance < 4 -> 0
            distance < 10 -> 0.5
            distance < 20 -> 1
            distance < 40 -> 1.5
            distance < 60 -> 2
            true -> 3
          end

        %{
          value: %{
            speed: speed,
            time: forward_time
          },
          duration: forward_time
        }
      end
    end
  end

  defp turn_other_valuator() do
    fn %{proximity: proximity, direction: direction, food_detected: food_detected?} ->
      if food_detected? or proximity == :unknown do
        nil
      else
        turn_direction = if direction < 0, do: :left, else: :right
        abs_direction = abs(direction)

        turn_time =
          cond do
            abs_direction == 0 -> 0
            abs_direction <= 30 -> 0.5
            abs_direction <= 60 -> 1
            abs_direction <= 90 -> 1.5
            true -> 2
          end

        %{
          value: %{
            turn_direction: turn_direction,
            turn_time: turn_time
          },
          duration: turn_time
        }
      end
    end
  end

  defp wait_track_other_valuator() do
    fn %{proximity: proximity, direction: direction, food_detected: food_detected?} ->
      time = if food_detected? or proximity == :unknown or direction == :unknown, do: 0, else: 0.5
      %{value: %{time: time}, duration: time}
    end
  end

  defp go_forward_other_valuator() do
    fn %{proximity: proximity, food_detected: food_detected?} ->
      if food_detected? or proximity == :unknown do
        nil
      else
        speed =
          cond do
            proximity < 2 -> :very_slow
            proximity < 5 -> :slow
            proximity < 7 -> :normal
            true -> :fast
          end

        forward_time =
          cond do
            proximity == 0 -> 0
            proximity < 3 -> 0.5
            proximity < 5 -> 1
            proximity < 7 -> 2
            true -> 3
          end

        %{
          value: %{
            speed: speed,
            time: forward_time
          },
          duration: forward_time
        }
      end
    end
  end

  #

  defp food_detected?(round, about) do
    %{distance: distance, heading: heading} =
      current_perceived_values(round, about, :location_of_food,
        default: %{distance: :unknown, heading: :unknown}
      )

    not (distance == :unknown or heading == :unknown)
  end
end
