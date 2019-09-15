defmodule Andy.Profiles.Rover.GMDefs.Freedom do
  @moduledoc "The GM definition for :freedom"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :freedom,
      conjectures: [
        conjecture(:free)
      ],
      contradictions: [],
      priors: %{free: %{about: :self, values: %{is: true}}},
      intentions: %{
        express_opinion_about_freedom: %Intention{
          intent_name: :say,
          valuator: opinion_about_freedom(),
          repeatable: false
        },
        roam_about: %Intention{
          intent_name: :move,
          valuator: roam_valuator()
        }
      }
    }
  end

  # Conjectures

  # opinion
  defp conjecture(:free) do
    %Conjecture{
      name: :free,
      activator: opinion_activator(),
      predictors: [],
      valuator: free_belief_valuator(),
      intention_domain: [:express_opinion_about_freedom, :roam_about]
    }
  end

  # Conjecture belief valuators

  defp free_belief_valuator() do
    fn _conjecture_activation, _rounds ->
      %{is: true}
    end
  end

  # Intention valuators

  defp opinion_about_freedom() do
    fn %{is: free?} ->
      if free?, do: saying("Let's check things out"), else: nil
    end
  end
end
