defmodule Andy.Intent do
  @moduledoc "A struct for an intent (a unit of intention to act)"

  import Andy.Utils
  alias __MODULE__

  @type t :: %__MODULE__{
          about: atom,
          value: any,
          since: number
        }

  @doc """
  about: The nature of the intent
  value: The measure of the intent (a number, atom...)
  since: When the intent was created
  source: The source of the intent
  """
  defstruct about: nil,
            value: nil,
            since: nil

  @doc "Create an intent"
  def new(about: about, value: params) do
    %Intent{
      about: about,
      since: now(),
      value: params
    }
  end

  @doc "The age of an intent"
  def age(intent) do
    now() - intent.since
  end

end

defimpl Inspect, for: Andy.Intent do
  def inspect(intent, _opts) do
    "<Intent #{inspect(intent.about)} #{inspect intent.value}>"
  end
end

