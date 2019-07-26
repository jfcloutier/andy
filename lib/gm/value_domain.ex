defprotocol Andy.GM.ValueDomain do
  @moduledoc "Protocol for data structures defining value domains of the parameters of conjectures and predictions"

  @doc "Is a value in a domain"
  def in_domain?(domain, value)

  @doc "What is the size of a domain?"
  def size(domain)
end

defimpl Andy.GM.ValueDomain, for: List do
  def in_domain?(list, value), do: value in list
  def size(list), do: length(list)
end

defimpl Andy.GM.ValueDomain, for: Range do
  def in_domain?(range, value), do: value in range
  def size(a..b), do: max(a, b) - min(a, b) + 1
end
