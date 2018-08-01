defmodule Andy.Mommy.Profile do
	
	@moduledoc "A mommy's profile"

	@behaviour Andy.ProfileBehaviour

  def generative_models() do
    Andy.Mommy.Modeling.generative_models()
  end

end
