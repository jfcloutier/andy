defmodule Andy.Percept do
  @moduledoc "A struct for a percept (a detected value for a sense)."

  import Andy.Utils

  defstruct id: nil,
            about: nil,
              # What is being perceived - %{class: class, port: port, type: type, sense: sense}
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
  def new(about: about, value: value) do
    msecs = now()
    %Andy.Percept{
      id: UUID.uuid4(),
      about: about,
      since: msecs,
      until: msecs,
      value: value
    }
  end

  @doc "Create a new percept with sense, value and source set"
  def new(about: about, value: value, source: source) do
    msecs = now()
    %Andy.Percept{
      id: UUID.uuid4(),
      about: about,
      since: msecs,
      until: msecs,
      value: value,
      source: source
    }
  end

  @doc "Create a new percept with sense, value and source set"
  def new(about: about, value: value, source: source, ttl: ttl) do
    msecs = now()
    %Andy.Percept{
      id: UUID.uuid4(),
      about: about,
      since: msecs,
      until: msecs,
      value: value,
      source: source,
      ttl: ttl
    }
  end

  @doc "Create a new transient percept with sense, value set"
  def new_transient(about: about, value: value) do
    msecs = now()
    %Andy.Percept{
      id: UUID.uuid4(),
      about: about,
      since: msecs,
      until: msecs,
      value: value,
      transient: true
    }
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
  def sense(
        %{
          about: %{
            sense: sense
          }
        } = _percept
      ) do
    sense
  end

  def transient?(percept) do
    percept.transient
  end

  def about_match?(about1, about2) do
    # Both have the same keys
    keys = Map.keys(about1)
    Enum.all?(
      keys,
      fn (key) -> val1 = Map.fetch!(about1, key)
                  val2 = Map.fetch!(about2, key)
                  val1 == "*"
                  or val2 == "*"
                  or val1 == val2
      end
    )
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
