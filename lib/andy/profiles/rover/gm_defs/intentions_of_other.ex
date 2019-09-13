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

  # opinion
  defp conjecture(:other_panicking) do
    %Conjecture{
      name: :other_panicking,
      # Only activate if actively observing the robot
      activator: opinion_activator(:other),
      predictors: [
        no_change_predictor(:observed,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )
      ],
      valuator: other_panicking_belief_valuator(),
      intention_domain: [:say_other_panicking]
    }
  end

  # opinion
  defp conjecture(:other_homing_on_food) do
    %Conjecture{
      name: :other_homing_on_food,
      activator: opinion_activator(:other),
      predictors: [
        no_change_predictor(:observed,
          default: %{is: false, proximity: :unknown, direction: :unknown}
        )
      ],
      valuator: other_homing_on_food_belief_valuator(),
      intention_domain: [:say_other_homing_on_food]
    }
  end

  # Conjecture belief valuators

  defp other_panicking_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 15_000
        )

      proximities = Enum.map(observations, &Map.get(&1, :proximity, :unknown))
      directions = Enum.map(observations, &Map.get(&1, :direction, :unknown))

      panicking? =
        Enum.count(observations) > 4 and
          reversals(proximities) > 3 and
          reversals(directions) > 3

      %{is: panicking?}
    end
  end

  defp other_homing_on_food_belief_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      observations =
        recent_perceived_values(rounds, about, :observed,
          matching: %{is: true},
          since: now() - 15_000
        )

      proximities = Enum.map(observations, &Map.get(&1, :proximity, :unknown))
      directions = Enum.map(observations, &Map.get(&1, :direction, :unknown))

      homing? =
        Enum.count(observations) > 4 and
          count_changes(proximities) > 4 and
          reversals(proximities) <= 1 and
          reversals(directions) <= 1

      {believed_proximity, believed_direction} =
        case observations do
          [] ->
            :unknown

          [%{proximity: proximity, direction: direction} | _] ->
            {proximity, direction}
        end

      %{is: homing?, proximity: believed_proximity, direction: believed_direction}
    end
  end

  # Intention valuators

  defp panicking_opinion_valuator() do
    fn %{is: true} ->
      saying("#{Andy.name_of_other()} is freaking out")
    end

    fn _ ->
      nil
    end
  end

  defp homing_on_food_opinion_valuator() do
    fn %{is: true} ->
      saying("#{Andy.name_of_other()} has found food")
    end

    fn _ ->
      nil
    end
  end
end
