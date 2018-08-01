defmodule Andy.ProfileBehaviour do

	@moduledoc "Behaviour for a profile"

@doc "The generative models for the profile"
	@callback generative_models() :: [GenerativeModel.t]

end
	
