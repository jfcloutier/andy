defmodule Andy.Profiles.Rover.GMDefs.Being do
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
      priors: %{thriving: %{about: :self, values: %{is: true}}},
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
      self_activated: true,
      activator: opinion_activator(:self),
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
      safe? = current_perceived_value(round, about, :safe, :is, default: true)

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
      safe? = current_perceived_value(round, about, :safe, :is, default: true)
      sated? = current_perceived_value(round, about, :sated, :is, default: true)

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

  # Conjecture belief valuators

  defp thriving_belief_valuator() do
    fn conjecture_actuation, [round | _previous_rounds] ->
      about = conjecture_actuation.about
      sated? = current_perceived_value(round, about, :sated, :is, default: true)
      safe? = current_perceived_value(round, about, :safe, :is, default: true)
      free? = current_perceived_value(round, about, :free, :is, default: true)
      %{is: safe? and sated? and free?}
    end
  end

  # Intention valuators

  defp opinion_about_thriving() do
    fn %{is: thriving?} ->
      if thriving?, do: saying("Life is good"), else: saying("Life sucks")
    end
  end
end
