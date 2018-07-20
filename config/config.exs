# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Customize non-Elixir parts of the firmware.  See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.
config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Use shoehorn to start the main application. See the shoehorn
# docs for separating out critical OTP applications such as those
# involved with firmware updates.
config :shoehorn,
       init: [:nerves_runtime, :nerves_init_gadget],
       app: Mix.Project.config()[:app]

# The following fragment inserts your id_rsa.pub at compile time
config :nerves_firmware_ssh,
       authorized_keys: [
         File.read!(Path.join(System.user_home!, ".ssh/id_rsa_ev3.pub"))
       ]

# Add to ~/.ssh/config

# Host nerves-*
# UserKnownHostsFile /dev/null
# StrictHostKeyChecking no
# IdentityFile ~/.ssh/id_rsa_ev3

# Edit upload.sh, after doing `mix firmware.gen.script` once

# SSH_OPTIONS="$SSH_OPTIONS -b $LINK_LOCAL_IP -i /home/jf/.ssh/id_rsa_ev3"


# Replace the default Elixir logger
config :logger, backends: [RingLogger]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.Project.config[:target]}.exs"

# wifi config - Only use Tenda USB modems
key_mgmt = System.get_env("NERVES_NETWORK_KEY_MGMT") || "WPA-PSK"
config :nerves_network,
       regulatory_domain: "US"

config :nerves_network,
       :default,
       wlan0: [
         ssid: System.get_env("NERVES_NETWORK_SSID"),
         psk: System.get_env("NERVES_NETWORK_PSK"),
         key_mgmt: String.to_atom(key_mgmt)
       ],
       eth0: [
         ipv4_address_method: :dhcp
       ]