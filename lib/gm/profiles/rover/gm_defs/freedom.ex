defmodule Andy.GM.Profiles.Rover.GMDefs.Freedom do
  @moduledoc "The GM definition for :danger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :freedom,
      conjectures: [
        conjecture(:free)
      ],
      contradictions: [],
      priors: %{free: %{is: true}},
      intentions: %{
        express_opinion_about_freedom: %Intention{
          intent_name: :say,
          valuator: opinion_about_freedom(),
          repeatable: false
        },
        roam_about: %Intention{
          itent_name: :roam,
          valuator: roam_valuator()
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:free) do
    %Conjecture{
      name: :free,
      activator: always_activator(:opinion),
      predictors: [],
      valuator: free_valuator(),
      intention_domain: [:express_opinion_about_freedom, :roam_about]
    }
  end

  # Conjecture activators

  # Conjecture predictors

  # Conjecture belief valuators

  defp free_valuator() do
    fn conjecture_activation, rounds ->
      %{is: true}
    end
  end

  # Intention valuators

  defp opinion_about_freedom() do
    fn %{is: true} ->
      "Let's explore"
    end

    fn _other ->
      "I feel trapped"
    end
  end

  defp roam_valuator() do
    %{forward_speed: Enum.random([:fast, :normal, :slow]),
      forward_time: Enum.random(0..3),
      turn_direction: Enum.random([:left, :right]),
      turn_time: Enum.random(0..4)
      }
  end
end
