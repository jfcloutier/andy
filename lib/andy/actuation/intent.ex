defmodule Andy.Intent do
  @moduledoc "A struct for an intent (a unit of intention to act)"

  import Andy.Utils
  alias __MODULE__

  # half a second
  @default_duration 0.5
  @stale_after 2_000

  @type t :: %__MODULE__{
          id: String.t(),
          about: atom,
          value: any,
          since: non_neg_integer,
          duration: number,
          executed: boolean
        }

  @doc """
  about: The nature of the intent
  value: The measure of the intent (a number, atom...)
  since: When the intent was created
  source: The source of the intent
  """
  defstruct id: nil,
            about: nil,
            value: nil,
            since: nil,
            duration: @default_duration,
            executed: false

  @doc "Create an intent"
  def new(about: about, value: params, duration: duration) do
    %Intent{
      id: UUID.uuid4(),
      about: about,
      since: now(),
      value: params,
      duration: duration
    }
  end

 @doc "The default duration of an intent"
 def default_duration() do
   @default_duration
  end

  @doc "The age of an intent"
  def age(intent) do
    now() - intent.since
  end

  @doc "Whether the intent was executed"
  def executed?(intent) do
    intent.executed
  end

  @doc "Whether the intent is stale"
  def stale?(intent) do
    age(intent) > @stale_after
  end
end

defimpl Inspect, for: Andy.Intent do
  def inspect(intent, _opts) do
    "<Intent #{inspect(intent.about)} #{inspect(intent.value)}>"
  end
end
