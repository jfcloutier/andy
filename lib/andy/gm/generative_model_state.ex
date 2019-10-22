defmodule Andy.GM.State do
  defstruct gm_def: nil,
              # a GenerativeModelDef - static
              # Names of the generative models this GM feeds into according to the GM graph
            super_gm_names: [],
              # Names of the generative models that feed into this GM according to the GM graph
            sub_gm_names: [],
              # Whether the GM has finished starting its first round
            started: false,
              # Conjecture activations, some of which can be goals. One conjecture can lead to multiple activations,
              # each about a different object
            conjecture_activations: [],
              # latest rounds of activation of the generative model
            rounds: [],
              # precision weights currently given to sub-GMs and detectors => float from 0 to 1 (full weight)
            precision_weights: %{},
              # conjecture_activation_subject => [efficacy, ...] - the efficacies of tried courses of action to achieve a goal conjecture
            efficacies: %{},
              # conjecture_activation_subject => index of next course of action to try
            courses_of_action_indices: %{},
              # one [:initializing, :running, :completing, :closing, :shutdown]
            round_status: :initializing,
              # event bufer for when current round in not running
            event_buffer: []
end
