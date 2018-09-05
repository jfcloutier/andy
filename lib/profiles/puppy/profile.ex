defmodule Andy.Puppy.Profile do
	
	@moduledoc "A puppy's profile"

	@behaviour Andy.ProfileBehaviour

	def conjectures() do
    Andy.Puppy.Modeling.conjectures()
  end

end
