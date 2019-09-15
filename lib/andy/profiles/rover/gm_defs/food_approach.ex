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
      contradictions: [[:closer_to_food, :closer_to_other_homing]],
      priors: %{
        closer_to_food: %{
          about: :self,
          values: %{is: false, distance: :unknown, heading: :unknown}
        },
        closer_to_other: %{
          about: :other,
          values: %{is: false, proximity: :unknown, direction: :unknown}
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
      activator: closer_to_other_homing_activator(),
      predictors: [
        no_change_predictor(:other_homing_on_food,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )
      ],
      valuator: closer_to_other_homing_belief_valuator(),
      intention_domain: [:track_other]
    }
  end

  # Conjecture activators

  defp closer_to_other_homing_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      food_detected? = food_detected?(round, prediction_about)

      if not food_detected? do
        [
          Conjecture.activate(conjecture,
            about: prediction_about,
            goal: fn %{is: closer_to_other_homing?} -> closer_to_other_homing? end
          )
        ]
      else
        []
      end
    end
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
    fn _conjecture_activation, [round | _previous_rounds] = rounds ->
      approaching? =
        numerical_perceived_value_trend(rounds, :other_homing_on_food, :other, :proximity) ==
          :decreasing

      other_vector =
        current_perceived_values(round, :other, :other_homing_on_food,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )

      %{
        is: approaching?,
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
            distance < 20 -> :slow
            distance < 40 -> :normal
            true -> :fast
          end

        forward_time =
          cond do
            distance < 5 -> 0.25
            distance < 10 -> 0.5
            distance < 20 -> 1
            distance < 60 -> 1.5
            true -> 2
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
    fn %{proximity: proximity, direction: direction} ->
      if proximity == :unknown do
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
    fn %{proximity: proximity, direction: direction} ->
      time = if proximity == :unknown or direction == :unknown, do: 0, else: 0.5
      %{value: %{time: time}, duration: time}
    end
  end


  defp go_forward_other_valuator() do
    fn %{proximity: proximity} ->
      if proximity == :unknown do
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
