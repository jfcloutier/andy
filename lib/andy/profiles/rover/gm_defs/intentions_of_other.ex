defmodule Andy.Profiles.Rover.GMDefs.IntentionsOfOther do
  @moduledoc "The GM definition for :intentions_of_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  def gm_def() do
    %GenerativeModelDef{
      name: :intentions_of_other,
      conjectures: [
        conjecture(:other_panicking),
        conjecture(:other_panicking)
      ],
      # allow all conjectures to be activated
      contradictions: [],
      priors: %{
        other_panicking: %{about: :other, values: %{is: false}},
        other_homing_on_food: %{about: :other, values: %{is: false}}
      },
      intentions: %{
        say_other_panicking: %Intention{
          intent_name: :say,
          valuator: panicking_opinion_valuator(),
          repeatable: false
        },
        say_other_homing_on_food: %Intention{
          intent_name: :say,
          valuator: homing_on_food_opinion_valuator(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:other_panicking) do
    %Conjecture{
      name: :other_panicking,
      # Only activate if actively observing the robot
      activator: always_activator(:opinion, :other),
      predictors: [
        no_change_predictor(:observed, default: %{is: false, proximity: :unknown, direction: :unknown})
      ],
      valuator: other_panicking_belief_valuator(),
      intention_domain: [:say_other_panicking]
    }
  end

  defp conjecture(:other_homing_on_food) do
    %Conjecture{
      name: :other_homing_on_food,
      # Only activate if actively observing the robot
      activator: always_activator(:opinion, :other),
      predictors: [
        no_change_predictor(:observed, default: %{is: false, proximity: :unknown, direction: :unknown})
      ],
      valuator: other_homing_on_food_belief_valuator(),
      intention_domain: [:say_other_homing_on_food]
    }
  end

  # Conjecture activators

  # Conjecture predictors

  # Conjecture belief valuators

  defp other_panicking_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 10_000
        )

      proximities = Enum.map(observations, &Map.get(&1, :proximity_mod, :unknown))
      directions = Enum.map(observations, &Map.get(&1, :direction_mod, :unknown))

      panicking? =
        Enum.count(observations) > 4 and
          reversals(proximities) > 3 and
          reversals(directions) > 3

      %{is: panicking?}
    end
  end

  defp other_homing_on_food_belief_valuator() do
    fn conjecture_activation, [round | _previous_rounds] = rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 10_000
        )

      proximities = Enum.map(observations, &Map.get(&1, :proximity_mod, :unknown))
      directions = Enum.map(observations, &Map.get(&1, :direction_mod, :unknown))

      homing? =
        Enum.count(observations) > 4 and
          count_changes(proximities) > 4 and
          reversals(proximities) <= 1 and
          reversals(directions) <= 1

      proximity = current_perceived_value(round, about, :proximity_mod, :detected, defaut: :unknown)
      direction = current_perceived_value(round, about, :direction_mod, :detected, defaut: :unknown)
      %{is: homing?,
        proximity: proximity,
        direction: direction}
    end
  end

  # Intention valuators

  defp panicking_opinion_valuator() do
    fn %{is: true} ->
      "#{Andy.name_of_other()} is freaking out"
    end

    fn _ ->
      nil
    end
  end

  defp homing_on_food_opinion_valuator() do
    fn %{is: true} ->
      "#{Andy.name_of_other()} has found food"
    end

    fn _ ->
      nil
    end
  end
end
