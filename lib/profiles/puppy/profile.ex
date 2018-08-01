defmodule Andy.Puppy.Profile do
	
	@moduledoc "A puppy's profile"

	@behaviour Andy.ProfileBehaviour

	def generative_models() do
    Andy.Puppy.Modeling.generative_models()
  end

end
