defmodule Andy.Mommy.Profile do
	
	@moduledoc "A mommy's profile"

	@behaviour Andy.ProfileBehaviour

  def conjectures() do
    Andy.Mommy.Profiling.conjectures()
  end

end
