defmodule Andy.GM.Profiles.Rover.GMDefs.ObservingOtherRover do
  @moduledoc "The GM definition for :observing_other_rover"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :observing_other_rover,
      conjectures: [
        conjecture(:other_not_seen),
        conjecture(:observing),
      ],
      contradictions: [[:other_not_seen, :observing]],
      priors: %{other_not_seen: %{is: true}, observing: %{is: false}},
      intentions: %{
        scan_right: %Intention{
          intent_name: :scan,
          valuator: scan_valuator(:right),
          repeatable: true
        },
        scan_left: %Intention{
          intent_name: :scan,
          valuator: scan_valuator(:left),
          repeatable: true
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:other_not_seen) do
    %Conjecture{
      name: :other_not_seen,
      activator: always_activator(:opinion, :other),
      predictors: [
        no_change_predictor("*:*:distance", default: %{detected: -128})
      ],
      valuator: other_not_seen_belief_valuator(),
      intention_domain: []
    }
  end

  defp conjecture(:observing) do
    %Conjecture{
      name: :other_not_seen,
      activator: observing_activator(),
      predictors: [
        no_change_predictor("*:*:distance/#{channel_of_other()}", default: %{detected: -128}),
        no_change_predictor("*:*:heading/#{channel_of_other()}", default: %{detected: 0})
      ],
      valuator: observing_valuator(),
      intention_domain: [:scan_right, :scan_left]
    }
  end


  # Conjecture activators

  defp observing_activator() do
    fn conjecture, rounds ->
      recently_observing? = once_believed?(:observing, :other, :is, true, now() - 10_000, rounds)
      if not recently_observing? do
      [
        Conjecture.activate(conjecture,
          about: :other,
          goal?: true
        )
      ]
      else
      []
      end
    end
  end

  # TODO

  # Conjecture predictors

  # Conjecture belief valuators

  defp distance_to_obstacle_valuator() do
    fn conjecture_activation, [round, _previous_rounds] ->
      about = conjecture_activation.about

      distance = current_perceived_value("*:*:distance", :detected, about, round, default: -128)

      if distance == -128 do
        %{is: :unknown}
      else
        %{is: distance}
      end
    end
  end

  # Intention valuators

  defp opinion_about_distance() do
    fn (%{is: distance}) when distance < 10 -> "Oops!" end
    fn (_)  -> nil end
  end

end
