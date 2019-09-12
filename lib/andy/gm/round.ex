defmodule Andy.GM.Round do
  @moduledoc "A round for a generative model. Also serves as episodic memory."

  alias __MODULE__
  alias Andy.GM.GenerativeModelDef

  defstruct id: nil,
            # = the Nth round
            index: nil,
            started_on: nil,
            # timestamp of when the round was completed. Nil if on-going
            completed_on: nil,
            # names of sub-GMs that reported a completed round
            reported_in: [],
            # Uncontested predictions made by the GM and prediction errors from sub-GMs and detectors
            perceptions: [],
            # [prediction, ...] predictions reported by super-GMs about this GM's next beliefs
            received_predictions: [],
            # beliefs in this GM conjecture activations given perceptions (own predictions and prediction errors
            # from sub-GMs and detectors)
            beliefs: [],
            # [course_of_action, ...] - courses of action (to be) taken to achieve goals and/or shore up beliefs
            courses_of_action: [],
            # intents executed in the round
            intents: [],
            # whether round is on an early timeout (otherwise would have completed too soon
            early_timeout_on: false

  def new(index \\ 0) do
    %Round{id: UUID.uuid4(), index: index}
  end

  def initial_round(gm_def) do
    %Round{Round.new() | beliefs: GenerativeModelDef.initial_beliefs(gm_def)}
  end

  def next_round_index([round | _]) do
    round.index + 1
  end

  def started?(%Round{started_on: started_on}) do
    started_on != nil
  end
end
