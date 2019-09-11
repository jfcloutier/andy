defmodule Andy.Profiles.Rover.GMDefs.SeekingFood do
  @moduledoc "The GM definition for :seeking_food"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :seeking_food,
      conjectures: [
        conjecture(:over_food),
        conjecture(:no_food),
        conjecture(:other_found_food)
      ],
      contradictions: [
        [:over_food, :no_food]
      ],
      priors: %{
        over_food: %{about: :self, values: %{is: false}},
        no_food: %{about: :self, values: %{is: true}},
        other_found_food: %{about: :other, values: %{is: false}}
      },
      intentions:
        %{
          track_other: %Intention{
            intent_name: :move,
            valuator: tracking_other_valuator(),
            repeatable: true
          },
          track_food: %Intention{
            intent_name: :move,
            valuator: tracking_food_valuator(),
            repeatable: true
          }
        }
        |> Map.merge(movement_intentions())
    }
  end

  # Conjectures

  defp conjecture(:no_food) do
    %Conjecture{
      name: :no_food,
      activator: always_activator(:opinion, :self),
      predictors: [
        no_change_predictor("*:*:beacon_heading/1", default: %{detected: 0}),
        no_change_predictor("*:*:beacon_distance/1", default: %{detected: :unknown})
      ],
      valuator: no_food_belief_valuator(),
      intention_domain: movement_domain(),
      self_activated: true
    }
  end

  defp conjecture(:over_food) do
    %Conjecture{
      name: :over_food,
      activator: over_food_activator(),
      predictors: [
        no_change_predictor("*:*:color", default: %{detected: :unknown}),
        no_change_predictor("*:*:beacon_heading/1", default: %{detected: 0}),
        no_change_predictor("*:*:beacon_distance/1", default: %{detected: :unknown})
      ],
      valuator: over_food_belief_valuator(),
      intention_domain: [:track_food]
    }
  end

  defp conjecture(:other_found_food) do
    %Conjecture{
      name: :other_found_food,
      activator: other_found_food_activator(),
      predictors: [
        no_change_predictor(:other_homing_on_food,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )
      ],
      valuator: other_found_food_belief_valuator(),
      intention_domain: [:track_other]
    }
  end

  # Conjecture activators

  defp other_found_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      food_detected? = food_detected?(round, prediction_about)
      over_food? = over_food?(round, prediction_about)

      if not over_food? and not food_detected? do
        [
          Conjecture.activate(conjecture,
            about: prediction_about
          )
        ]
      else
        []
      end
    end
  end

  defp over_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      over_food? = over_food?(round, prediction_about)

      food_detected? = food_detected?(round, prediction_about)

      if not over_food? and food_detected? do
        [
          Conjecture.activate(conjecture,
            about: prediction_about,
            goal: fn %{is: over_food?} -> over_food? end
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp over_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      over_food? = over_food?(round, about)

      distance =
        current_perceived_value(round, about, "*:*:beacon_distance/1", :detected,
          default: :unknown
        )

      heading =
        current_perceived_value(round, about, "*:*:beacon_heading/1", :detected, default: 0)

      %{is: over_food?, distance: distance, heading: heading}
    end
  end

  defp no_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      food_detected? = food_detected?(round, about)

      %{is: not food_detected?}
    end
  end

  def other_found_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      other_homing_on_food? =
        current_perceived_value(round, about, :other_homing_on_food, :is, default: false)

      other_vector =
        current_perceived_values(round, about, :other_homing_on_food,
          default: %{proximity: :unknown, direction: :unknown}
        )

      %{
        is: other_homing_on_food?,
        proximity: other_vector.proximity,
        direction: other_vector.direction
      }
    end
  end

  # Intention valuators

  defp tracking_food_valuator() do
    fn %{distance: distance, heading: heading} ->
      if distance == :unknown or heading == :unknown do
        nil
      else
        speed =
          cond do
            distance < 5 -> :very_slow
            distance < 10 -> :slow
            distance < 20 -> :normal
            true -> :fast
          end

        forward_time =
          cond do
            distance < 5 -> 0
            distance < 10 -> 0.5
            distance < 20 -> 1
            distance < 40 -> 2
            true -> 3
          end

        turn_direction = if heading < 0, do: :left, else: :right
        abs_heading = abs(heading)

        turn_time =
          cond do
            abs_heading == 0 -> 0
            abs_heading < 10 -> 0.25
            abs_heading < 10 -> 0.5
            abs_heading < 20 -> 1
            true -> 2
          end

        %{
          value: %{
            forward_speed: speed,
            forward_time: forward_time,
            turn_direction: turn_direction,
            turn_time: turn_time
          },
          duration: forward_time + turn_time
        }
      end
    end
  end

  defp tracking_other_valuator() do
    fn %{proximity: proximity, direction: direction} ->
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

        turn_direction = if direction < 0, do: :left, else: :right
        abs_direction = abs(direction)

        turn_time =
          cond do
            abs_direction == 0 -> 0
            abs_direction <= 30 -> 0.25
            abs_direction <= 60 -> 0.5
            abs_direction <= 90 -> 1
            true -> 2
          end

        %{
          value: %{
            forward_speed: speed,
            forward_time: forward_time,
            turn_direction: turn_direction,
            turn_time: turn_time
          },
          duration: forward_time + turn_time
        }
      end
    end
  end

  #

  defp over_food?(round, about) do
    current_perceived_value(round, about, "*:*:color", :detected, default: :unknown) == :white
  end

  defp food_detected?(round, about) do
    current_perceived_value(round, about, "*:*:beacon_distance/1", :detected, default: :unknown) !=
      :unknown
  end
end