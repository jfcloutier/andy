defmodule Andy.Percept do
  @moduledoc "A struct for a percept (a unit of perception)."

  import Andy.Utils

  defstruct about: nil,
              # What is being perceived
            value: nil,
              # The measurement/value of the perception (a number, atom etc.)
            since: nil,
              # When the perception happened
            until: nil,
              # Time at which the perception is still unchanged
            source: nil,
              # The source of the perception (a detector)
            ttl: nil,
              # How long the percept is to be retained in memory
            resolution: nil,
              # The precision of the detector or perceptor. Nil if perfect resolution.
            transient: false      # If true, the percept will not be memorized

  @doc "Create a new percept with sense and value set"
  def new(about: sense, value: value) do
    msecs = now()
    %Andy.Percept{
      about: sense,
      since: msecs,
      until: msecs,
      value: value
    }
  end

  @doc "Create a new percept with sense, value and source set"
  def new(about: sense, value: value, source: source) do
    msecs = now()
    %Andy.Percept{
      about: sense,
      since: msecs,
      until: msecs,
      value: value,
      source: source
    }
  end

  @doc "Create a new percept with sense, value and source set"
  def new(about: sense, value: value, source: source, ttl: ttl) do
    msecs = now()
    %Andy.Percept{
      about: sense,
      since: msecs,
      until: msecs,
      value: value,
      source: source,
      ttl: ttl
    }
  end

  @doc "Create a new transient percept with sense, value set"
  def new_transient(about: sense, value: value) do
    msecs = now()
    %Andy.Percept{
      about: sense,
      since: msecs,
      until: msecs,
      value: value,
      transient: true
    }
  end

  @doc "Get the sense name, whether the sense is qualified or not"
  def unqualified_sense(%Andy.Percept{ about: { sense_name, _qualifier } }) do
    sense_name
  end

  def unqualified_sense(%Andy.Percept{ about: sense }) do
    sense
  end

  @doc "Get the sense qualifier, nil if none"
  def sense_qualifier(%Andy.Percept{ about: { _sense_name, qualifier } }) do
    qualifier
  end

  def sense_qualifier(%Andy.Percept{ }) do
    nil
  end

  @doc "Set the source"
  def source(percept, source) do
    %Andy.Percept{ percept | source: source }
  end

  @doc "Are two percepts essentially the same (same sense, value and source)?"
  def same?(percept1, percept2) do
    percept1.about == percept2.about
    and percept1.value == percept2.value
    and same_source?(percept1.source, percept2.source)
  end

  @doc "The age of the percept"
  def age(percept) do
    now() - percept.until
  end

  @doc "The sense of the percept"
  def sense(percept) do
    case percept.about do
      { sense, _qualifier }
      -> sense
      sense when is_atom(sense)
      -> sense
    end
  end

  def transient?(percept) do
    percept.transient
  end

  ### PRIVATE

  defp same_source?(source1, source2) when is_map(source1) and is_map(source2) do
    Map.equal?(source1, source2)
  end

  defp same_source?(source1, source2) do
    source1 == source2
  end

  # about, since and value are required for the percept to be memorable

end
