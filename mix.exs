defmodule Andy.MixProject do
  use Mix.Project

  @target System.get_env("MIX_TARGET") || "host"

  def project do
    [
      app: :andy,
      version: "0.1.0",
      elixir: "~> 1.4",
      target: @target,
      archives: [
        nerves_bootstrap: "~> 1.0"
      ],
      elixirc_paths: elixirc_paths(Mix.env),
      compilers: [:phoenix, :gettext] ++ Mix.compilers,
      deps_path: "deps/#{@target}",
      build_path: "_build/#{@target}",
      lockfile: "mix.lock.#{@target}",
      start_permanent: Mix.env() == :prod,
      aliases: [
        loadconfig: [&bootstrap/1]
      ],
      deps: deps()
    ]
  end

  # Starting nerves_bootstrap adds the required aliases to Mix.Project.config()
  # Aliases are only added if MIX_TARGET is set.
  def bootstrap(args) do
    Application.start(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: { Andy.Application, [] },
      extra_applications: extra_applications()
    ]
  end

  defp extra_applications() do
    [:logger, :logger_file_backend] ++ extra_applications(@target)
  end

  defp extra_applications("ev3") do
    [:ex_ncurses]
  end

  defp extra_applications(_any) do
    []
  end


  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      { :logger_file_backend, "~> 0.0.10" },
      { :phoenix, "~> 1.3.0" },
      { :phoenix_pubsub, "~> 1.0" },
      { :phoenix_html, "~> 2.10" },
      { :phoenix_live_reload, "~> 1.0", only: :dev },
      { :httpoison, "~> 0.11" },
      { :poison, "~> 3.1.0" },
      { :gettext, "~> 0.11" },
      { :cowboy, "~> 1.0" },
      { :elixir_uuid, "~> 1.2" }
    ] ++ deps(@target)
  end

  # Specify target specific dependencies
  defp deps("host"), do: []

  defp deps(target) do
    [
      { :nerves, "~> 1.0", runtime: false },
      { :shoehorn, "~> 0.2" },
      { :nerves_init_gadget, "~> 0.4" },
      { :nerves_runtime, "~> 0.4" },
      { :ex_ncurses, "~> 0.3" }
    ] ++ system(target)
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp system("ev3"), do: [{ :nerves_system_ev3, "~> 1.0", runtime: false }]
  defp system("rpi"), do: [{ :nerves_system_rpi, "~> 1.0", runtime: false }]
  defp system("rpi0"), do: [{ :nerves_system_rpi0, "~> 1.0", runtime: false }]
  defp system("rpi2"), do: [{ :nerves_system_rpi2, "~> 1.0", runtime: false }]
  defp system("rpi3"), do: [{ :nerves_system_rpi3, "~> 1.0", runtime: false }]
  defp system("bbb"), do: [{ :nerves_system_bbb, "~> 1.0", runtime: false }]
  defp system("qemu_arm"), do: [{ :nerves_system_qemu_arm, "~> 1.0", runtime: false }]
  defp system("x86_64"), do: [{ :nerves_system_x86_64, "~> 1.0", runtime: false }]
  defp system(target), do: Mix.raise("Unknown MIX_TARGET: #{target}")
end
