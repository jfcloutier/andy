defmodule Andy.GM.Profiles.Rover do
  @moduledoc "The cognition profile of a rover"

  def cognition() do
    %Cognition{gm_defs: [], children: %{}, detectors: []}
  end
end
