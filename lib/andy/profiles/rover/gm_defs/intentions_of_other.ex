defmodule Andy.Profiles.Rover.GMDefs.IntentionsOfOther do
  @moduledoc "The GM definition for :intentions_of_other"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Round}
  import Andy.GM.Utils
  import Andy.Utils, only: [now: 0]

  require Logger

  @moves ~w{go_forward go_backward turn_right turn_left turn move panic}a

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
      self_activated: true,
      predictors: [
        no_change_predictor(:observed,
          default: %{
            is: false,
            proximity: :unknown,
            direction: :unknown,
            duration: 0,
            recently_believed_or_tried?: false
          }
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
      self_activated: true,
      predictors: [
        no_change_predictor(:observed,
          default: %{
            is: false,
            proximity: :unknown,
            direction: :unknown,
            duration: 0,
            recently_believed_or_tried?: false
          }
        )
      ],
      valuator: other_homing_on_food_belief_valuator(),
      intention_domain: [:say_other_homing_on_food]
    }
  end

  # Conjecture belief valuators

  defp other_panicking_belief_valuator() do
    fn conjecture_activation, [_round | previous_rounds] ->
      about = conjecture_activation.about

      observations =
        previous_rounds
        |> rounds_since(now() - 15_000)
        |> longest_round_sequence(fn round ->
          not Enum.any?(Round.intent_names(round), &(&1 in @moves))
        end)
        |> perceived_values(about, :observed, matching: %{is: true})

      observation_count = observations |> Enum.count()

      proximity_reversals =
        Enum.map(observations, &Map.get(&1, :proximity, :unknown)) |> reversals()

      direction_reversals =
        Enum.map(observations, &Map.get(&1, :direction, :unknown)) |> reversals()

      panicking? =
        observation_count > 4 and
          proximity_reversals > 3 and
          direction_reversals > 2

      Logger.info(
        "Other panicking is #{panicking?} from observation_count=#{observation_count} > 4, proximity_reversals=#{
          proximity_reversals
        } > 3, direction_reversals=#{direction_reversals} > 3"
      )

      %{is: panicking?}
    end
  end

  defp other_homing_on_food_belief_valuator() do
    fn conjecture_activation, [_round | previous_rounds] ->
      about = conjecture_activation.about

      observations =
        previous_rounds
        |> rounds_since(now() - 15_000)
        |> longest_round_sequence(fn round ->
          not Enum.any?(Round.intent_names(round), &(&1 in @moves))
        end)
        |> perceived_values(about, :observed, matching: %{is: true})

      observation_count = observations |> Enum.count()

      proximities = Enum.map(observations, &Map.get(&1, :proximity, :unknown))
      proximity_changes = proximities |> count_changes()
      proximity_reversals = proximities |> reversals()

      direction_reversals =
        Enum.map(observations, &Map.get(&1, :direction, :unknown)) |> reversals()

      homing? =
        observation_count > 4 and
          proximity_changes > 4 and
          proximity_reversals <= 1 and
          direction_reversals <= 1

      Logger.info(
        "Other homing is #{homing?} from observation_count=#{observation_count} > 4, proximity_changes=#{
          proximity_changes
        } > 4, proximity_reversals=#{proximity_reversals} <= 1>, direction_reversals=#{
          direction_reversals
        } <= 1"
      )

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
    fn %{is: panicking?} ->
      if panicking?, do: saying("#{Andy.name_of_other()} is freaking out"), else: nil
    end
  end

  defp homing_on_food_opinion_valuator() do
    fn %{is: homing?} ->
      if homing?, do: saying("#{Andy.name_of_other()} has found food"), else: nil
    end
  end
end
