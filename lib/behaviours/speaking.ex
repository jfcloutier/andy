defmodule Andy.Speaking do

	alias Andy.Device

	@doc "The sound player says out loud the given words"
  @callback speak(sound_player :: %Device{}, words :: binary) :: %Device{}

end
