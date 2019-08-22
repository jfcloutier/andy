defmodule Andy.GM.Profiles.Rover.GMDefs.Hunger do
  @moduledoc "The GM definition for :hunger"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :hunger,
      conjectures: [
        conjecture(:sated)
      ],
      contradictions: [],
      priors: %{sated: %{is: true}},
      intentions: %{
        express_opinion_about_sated: %Intention{
          intent_name: :say,
          valuator: opinion_about_sated(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:sated) do
    %Conjecture{
      name: :sated,
      activator: sated_activator(),
      predictors: [
        no_change_predictor(:chewing, default: %{is: true})
      ],
      valuator: sated_valuator(),
      intention_domain: [:express_opinion_about_sated]
    }
  end

  # Conjecture activators

  # Always activate, and as opinion
  defp sated_activator() do
    fn conjecture, [_round | previous_rounds] ->
      chewings_count =
        count_perceived_since(:chewing, :self, %{is: true}, previous_rounds, now() - 20_000)

      if chewings_count < 3 do
        [
          Conjecture.activate(conjecture,
            about: :self,
            goal?: true
          )
        ]
      else
        []
      end
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  defp sated_valuator() do
    fn conjecture_activation, rounds ->
      about = conjecture_activation.about

      chewings_count = count_perceived_since(:chewing, :self, %{is: true}, rounds, now() - 20_000)

      %{is: chewings_count >= 3}
    end
  end

  # Intention valuators

  defp opinion_about_sated() do
    fn %{is: false} ->
      "I am hungry"
    end

    fn _other ->
      nil
    end
  end
end
