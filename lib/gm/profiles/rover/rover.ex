defmodule Andy.GM.Profiles.Rover do
  @moduledoc "The cognition profile of a rover"

  alias Andy.GM.Cognition

  #

  def cognition() do
    %Cognition{gm_defs: [], children: %{}}
  end
end
