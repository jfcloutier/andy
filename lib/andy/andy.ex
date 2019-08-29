defmodule Andy do
  require Logger
  alias Andy.GM.{LongTermMemory, PubSub}

  import Andy.Utils,
    only: [platform_dispatch: 1, platform_dispatch: 2, profile_dispatch: 1, get_andy_env: 2]

  @default_ttl 10_000

  def shutdown() do
    PubSub.notify_shutdown()
  end

  def forget() do
    LongTermMemory.forget_everything()
  end

  def platform() do
    platform_name = get_andy_env("ANDY_PLATFORM", "mock_rover")
    platforms = Application.get_env(:andy, :platforms)
    Map.get(platforms, platform_name)
  end

  def profile() do
    profile_name = get_andy_env("ANDY_PROFILE", "rover")
    profiles = Application.get_env(:andy, :profiles)
    Map.get(profiles, profile_name)
  end

  def system() do
    get_andy_env("ANDY_SYSTEM", "pc")
  end

  def start_platform() do
    platform_dispatch(:start)
  end

  def platform_ready?() do
    platform_dispatch(:ready?)
  end

  # GM
  def cognition() do
    profile_dispatch(:cognition)
  end

  def display(words) do
    platform_dispatch(:display, [words])
  end

  def community_name() do
    get_andy_env("ANDY_COMMUNITY", "andy")
  end

  def default_ttl(kind) do
    (Application.get_env(:andy, :ttl) || [])
    |> Keyword.get(kind, @default_ttl)
  end

  def rest_port() do
    {port, _} =
      get_andy_env("ANDY_PORT", "4000")
      |> Integer.parse()

    port
  end

  def channel_of_other() do
    get_andy_env("ANDY_OTHER_CHANNEL", 3)
  end

  def name_of_other() do
    get_andy_env("ANDY_OTHER_NAME", "marv")
  end

  def ports_config() do
    platform_dispatch(:ports_config)
  end

  def sensors() do
    platform_dispatch(:sensors)
  end

  def motors() do
    platform_dispatch(:motors)
  end

  def leds() do
    platform_dispatch(:leds)
  end

  def sound_players() do
    platform_dispatch(:sound_players)
  end

  def perception_logic() do
    profile_dispatch(:perception_logic)
  end

  def conjectures() do
    profile_dispatch(:conjectures)
  end

  def actuation_logic() do
    platform_dispatch(:actuation_logic)
  end

  def id_channel() do
    String.to_integer(get_andy_env("ANDY_ID_CHANNEL", "0"))
  end

  def senses_for_id_channel(id_channel) do
    platform_dispatch(:senses_for_id_channel, [id_channel])
  end

  def device_mode(device_type) do
    platform_dispatch(:device_mode, [device_type])
  end

  def device_code(device_type) do
    platform_dispatch(:device_code, [device_type])
  end

  def in_probable_range?(probability, precision) do
    case precision do
      :high ->
        probability >= 0.8

      :medium ->
        probability >= 0.6

      :low ->
        probability >= 0.3

      :none ->
        true
    end
  end

  @doc "Of two levels give the highest one"
  def highest_level(level1, level2) do
    cond do
      :high in [level1, level2] -> :high
      :medium in [level1, level2] -> :medium
      :low in [level1, level2] -> :low
      true -> :none
    end
  end

  @doc "Of two levels give the lowest one"
  def lowest_level(level1, level2) do
    cond do
      :none in [level1, level2] -> :none
      :low in [level1, level2] -> :low
      :medium in [level1, level2] -> :medium
      true -> :high
    end
  end

  @doc "Is the first level higher than the second?"
  def higher_level?(level1, level2) do
    level1 != level2 and
      highest_level(level1, level2) == level1
  end

  def lower_level?(level, level) do
    false
  end

  def lower_level?(level1, level2) do
    level1 == lowest_level(level1, level2)
  end

  def reduce_level_by(level, :none) do
    level
  end

  def reduce_level_by(_level, :high) do
    :none
  end

  def reduce_level_by(level, level) do
    :none
  end

  def reduce_level_by(:low, _level) do
    :none
  end

  def reduce_level_by(:medium, :low) do
    :low
  end

  def reduce_level_by(:high, :medium) do
    :low
  end

  def reduce_level_by(:high, :low) do
    :medium
  end
end
