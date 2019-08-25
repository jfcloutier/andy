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
          valuator: opinion_about_thriving(),
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
      valuator: thriving_belief_valuator(),
      intention_domain: [:express_opinion_about_life]
    }
  end

  # Conjecture activators

  defp sated_predictor() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about
      safe? = current_perceived_value(round, about, :safe, :is, default: false)

      if safe? do
        %Prediction{
          conjecture_name: :sated,
          about: about,
          expectations: current_perceived_values(round, about, :sated, default: %{is: true})
        }
      else
        nil
      end
    end
  end

  defp free_predictor() do
    fn conjecture_activation, [round | _previous_rounds] ->
      about = conjecture_activation.about
      safe? = current_perceived_value(round, about, :safe, :is, default: false)
      sated? = current_perceived_value(round, about, :sated, :is, default: false)

      if safe? and sated? do
        %Prediction{
          conjecture_name: :free,
          about: about,
          expectations: current_perceived_values(round, about, :free, default: %{is: true})
        }
      else
        nil
      end
    end
  end


  # Conjecture predictors

  # Conjecture belief valuators

  defp thriving_belief_valuator() do
    fn(conjecture_actuation, [round | _previous_rounds]) ->
    about = conjecture_actuation.about
    sated? = current_perceived_value(round, about, :sated, :is, default: false)
    safe? = current_perceived_value(round, about, :safe, :is, default: false)
    free? = current_perceived_value(round, about, :free, :is, default: false)
    %{is: safe? and sated? and free?}
    end
  end

  # Intention valuators

  defp opinion_about_thriving() do
    fn %{is: true} ->
      "Life is good"
    end

    fn _other ->
      "Life sucks"
    end
  end
end
