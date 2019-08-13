defmodule Andy.GM.Profiles.Rover.GMDefs.Roving do
  @moduledoc "The GM definition for :roving"

  alias Andy.GM.{GenerativeModelDef, Intention, Conjecture}

  def gm_def() do
    %GenerativeModelDef{
      name: :roving,
      conjectures: [
        conjecture(:safe),
        conjecture(:sated),
        conjecture(:free)
      ],
      contradictions: [],
      priors: %{safe: %{level: :high}, sated: %{level: :high}, free: %{level: :high}},
      intentions: %{
        express_safe: %Intention{
          intent_name: :say,
          valuator: say_valuator(:safe),
          repeatable: false
        },
        express_sated: %Intention{
          intent_name: :say,
          valuator: say_valuator(:sated),
          repeatable: false
        },
        express_free: %Intention{
          intent_name: :say,
          valuator: say_valuator(:free),
          repeatable: false
        }
      }
    }
  end

  # Conjectures

  defp conjecture(:safe) do
    %Conjecture{
      name: :safe,
      activator: fn conjecture, state -> [] end,
      value_domains: %{level: [:low, :medium, :high]},
      predictors: [],
      valuator: fn about, value, rounds -> %{level: :high} end,
      intention_domain: [:express_safe]
    }
  end

  # Conjecture activators

  # Always
  defp safe_activator() do
    fn conjecture, rounds ->
      [
        Conjecture.activate(conjecture,
          about: :self,
          goals: true
        )
      ]
    end
  end

  # Conjecture predictors

  # Conjecture belief valuators

  # Intention valuators

  defp say_valuator(:safe) do
    fn %{level: level} ->
      case level do
        :low -> "I don't like it here"
        :medium -> "I feel safe"
        :high -> "I feel totally safe"
        other -> "Safety level is #{other}"
      end
    end

    # No belief in :safe
    fn nil ->
      "Oh no! I'm scared!"
    end
  end

  defp say_valuator(:sated) do
    fn %{level: level} ->
      case level do
        :low -> "I feel a bit peckish"
        :medium -> "I am not hungry"
        :high -> "I am stuffed"
        other -> "Sated level is #{other}"
      end
    end

    # No belief in :sated
    fn nil ->
      "I'm starving!"
    end
  end

  defp say_valuator(:free) do
    fn %{level: level} ->
      case level do
        :low -> "I feeling a bit stuck"
        :medium -> "I can move"
        :high -> "I am free!"
        other -> "Sated level is #{other}"
      end
    end

    # No belief in :sated
    fn nil ->
      "Help! I am stuck!"
    end
  end
end
