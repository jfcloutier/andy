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
       AndyWeb.Endpoint,
       url: [
         host: "localhost"
       ],
       secret_key_base: "JabRQhGLCdiqwHKJiz7PzzliXg+/meHmY5BCLRHdit5RpwvRa0i4Wp1zPVoFoc7e",
       render_errors: [
         view: AndyWeb.ErrorView,
         accepts: ~w(html json)
       ],
       pubsub: [
         name: Andy.PubSub,
         adapter: Phoenix.PubSub.PG2
       ]

config :andy, :ttl,
       percept: 10_000


config :andy,
       platforms: %{
         "mock_rover" => Andy.MockRover.Platform,
         "rover" => Andy.Rover.Platform,
         "hub" => Andy.Hub.Platform
       },
       profiles: %{
         "puppy" => Andy.Puppy.Profile,
         "mommy" => Andy.Mommy.Profile
       },
       tick_interval: 1500,
       max_percept_age: 1500,
       max_motive_age: 3000,
       max_intent_age: 1500,
       strong_intent_factor: 3,
       max_beacon_channels: 3,
       very_fast_rps: 3,
       fast_rps: 2,
       normal_rps: 1,
       slow_rps: 0.5,
       very_slow_rps: 0.3

