defmodule Andy.Moving do
  alias Andy.Device

  @callback reset(motor :: %Device{}) :: %Device{}

  @callback set_speed(motor :: %Device{}, mode :: atom, speed :: number) :: %Device{}

  @callback reverse_polarity(motor :: %Device{}) :: %Device{}

  @callback set_duty_cycle(motor :: %Device{}, duty_cycle :: number) :: %Device{}

  @callback run(motor :: %Device{}) :: %Device{}

  @callback run_for(motor :: %Device{}, duration :: number) :: %Device{}

  @callback run_to_absolute(motor :: %Device{}, degrees :: number) :: %Device{}

  @callback run_to_relative(motor :: %Device{}, degrees :: number) :: %Device{}

  @callback coast(motor :: %Device{}) :: %Device{}

  @callback brake(motor :: %Device{}) :: %Device{}

  @callback hold(motor :: %Device{}) :: %Device{}

  @callback set_ramp_up(motor :: %Device{}, msecs :: number) :: %Device{}

  @callback set_ramp_down(motor :: %Device{}, msecs :: number) :: %Device{}
end
