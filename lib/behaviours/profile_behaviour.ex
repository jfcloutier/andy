defmodule Andy.ProfileBehaviour do

	@moduledoc "Behaviour for a profile"

@doc "The conjectures for the profile"
	@callback conjectures() :: [Conjecture.t]

end
	
