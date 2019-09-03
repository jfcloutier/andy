# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Replace the default Elixir logger
# config :logger, backends: [RingLogger]
config :logger,
       :console,
       level: :info,
       format: "$time $metadata[$level] $message\n",
       metadata: [:request_id]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.Project.config[:target]}.exs"

config :andy,
  platforms: %{
    "mock_rover" => Andy.MockRover.Platform,
    "rover" => Andy.Rover.Platform
  },
  #  andy.profiles: %{
  #    "puppy" => Andy.Puppy.Profile,
  #    "mommy" => Andy.Mommy.Profile
  #  },
  profiles: %{
    "rover" => Andy.Profiles.Rover
  },
  max_beacon_channels: 1,
  #       very_fast_rps: 3,
  #       fast_rps: 2,
  #       normal_rps: 1,
  #       slow_rps: 0.5,
  #       very_slow_rps: 0.3
  very_fast_rps: 1.5,
  fast_rps: 1,
  normal_rps: 0.5,
  slow_rps: 0.25,
  very_slow_rps: 0.15
