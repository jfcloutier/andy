defmodule Andy.GM.Profiles.Rover do
  @moduledoc "The cognition profile of a rover"

  alias Andy.GM.{Cognition}
  alias Andy.GM.Profiles.Rover.GMDefs.{Roving}
  #

  def cognition() do
    %Cognition{
      gm_defs: [Roving.gm_def()],
      children: %{roving: []}
    }
  end


end
