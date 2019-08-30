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
        over_food: %{is: false},
        no_food: %{is: true},
        other_found_food: %{is: false}
      },
      intentions: %{
        track_other: %Intention{
          intent_name: :roam,
          valuator: tracking_valuator(),
          repeatable: true
        },
        track_food: %Intention{
          intent_name: :roam,
          valuator: tracking_valuator(),
          repeatable: true
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:over_food) do
    %Conjecture{
      name: :over_food,
      activator: over_food_activator(),
      predictors: [
        no_change_predictor("*:*:color", default: %{detected: :mystery}),
        no_change_predictor("*:*:beacon_heading/1", default: %{detected: 0}),
        no_change_predictor("*:*:beacon_distance/1", default: %{detected: -128})
      ],
      valuator: over_food_belief_valuator(),
      intention_domain: [:track_food]
    }
  end

  defp conjecture(:no_food) do
    %Conjecture{
      name: :no_food,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor("*:*:beacon_heading/1", default: %{detected: 0}),
        no_change_predictor("*:*:beacon_distance/1", default: %{detected: -128})
      ],
      valuator: no_food_belief_valuator(),
      intention_domain: []
    }
  end

  defp conjecture(:other_found_food) do
    %Conjecture{
      name: :other_found_food,
      activator: other_found_food_activator(),
      predictors: [
        no_change_predictor(:other_homing_on_food, default: %{is: false})
      ],
      valuator: other_found_food_belief_valuator(),
      intention_domain: [:track_other]
    }
  end

  # Conjecture activators

  defp other_found_food_activator() do
    fn conjecture, [round | _previous_rounds], prediction_about ->
      other_homing_on_food? =
        current_perceived_value(round, prediction_about, :other_homing_on_food, :is, default: false)

      if other_homing_on_food? do
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
      white? =
        current_perceived_value(round, prediction_about, "*:*:color", :detected, default: :mystery) == :white

      food_detected? =
        current_perceived_value(round, prediction_about, "*:*:beacon_distance/1", :detected, default: -128) !=
          -128

      if not white? and food_detected? do
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

      white? =
        current_perceived_value(round, about, "*:*:color", :detected, default: :mystery) == :white

      distance =
        current_perceived_value(round, about, "*:*:beacon_distance/1", :detected, default: -128)

      heading =
        current_perceived_value(round, about, "*:*:beacon_heading/1", :detected, default: 0)

      %{is: white?, distance: distance, heading: heading}
    end
  end

  defp no_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      no_food_detected? =
        current_perceived_value(round, about, "*:*:beacon_heading/1", :detected, default: -128) ==
          -128

      %{is: no_food_detected?}
    end
  end

  def other_found_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about

      other_homing_on_food? =
        current_perceived_value(round, about, :other_homing_on_food, :is, default: false)

      other_eating? = current_perceived_value(round, about, :other_eating, :is, default: false)

      other_vector =
        current_perceived_values(round, about, :other_eating,
          default: %{distance: -128, heading: 0}
        )

      %{
        is: other_homing_on_food? or other_eating?,
        distance: other_vector.distance,
        heading: other_vector.heading
      }
    end
  end

  # Intention valuators

  defp tracking_valuator() do
    fn %{distance: distance, heading: heading} ->
      if distance == -128 do
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
          forward_speed: speed,
          forward_time: forward_time,
          turn_direction: turn_direction,
          turn_time: turn_time
        }
      end
    end
  end
end
