defmodule Andy.GM.Profiles.Rover.GMDefs.Being do
  @moduledoc "The GM definition for :being"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture, Prediction}
  import Andy.GM.Utils

  def gm_def() do
    %GenerativeModelDef{
      name: :being,
      conjectures: [
        conjecture(:thriving)
      ],
      contradictions: [],
      hyper_prior: true,
      priors: %{thriving: %{is: true}},
      intentions: %{
        express_opinion_about_life: %Intention{
          intent_name: :say,
          valuator: opinion_about_life(),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:thriving) do
    %Conjecture{
      name: :thriving,
      activator: always_activator(:opinion),
      predictors: [
        no_change_predictor(:safe, default: %{is: true}),
        sated_predictor(),
        free_predictor()
      ],
      valuator: fn about, value, rounds -> nil end,
      intention_domain: [:express_opinion_about_life]
    }
  end

  # Conjecture activators

  defp sated_predictor() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about
      safe? = current_perceived_value(:safe, :is, about, round, default: false)

      if safe? do
        %Prediction{
          conjecture_name: :sated,
          about: about,
          expectations: current_perceived_values(:sated, about, round, default: %{is: true})
        }
      else
        nil
      end
    end
  end

  defp free_predictor() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about
      safe? = current_perceived_value(:safe, :is, about, round, default: false)
      sated? = current_perceived_value(:sated, :is, about, round, default: false)

      if safe? and sated? do
        %Prediction{
          conjecture_name: :free,
          about: about,
          expectations: current_perceived_values(:free, about, round, default: %{is: true})
        }
      else
        nil
      end
    end
  end


  # Conjecture predictors

  # Conjecture belief valuators

  # Intention valuators

  defp opinion_about_life() do
    fn %{is: true} ->
      "Life is good"
    end

    fn _other ->
      "Life sucks"
    end
  end
end
