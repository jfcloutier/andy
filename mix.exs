defmodule Andy.MixProject do
  use Mix.Project

  @target System.get_env("MIX_TARGET") || "host"

  def project do
    [
      app: :andy,
      version: "0.2.0",
      elixir: "~> 1.8",
      target: @target,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Andy.GM.Application, []},
      extra_applications: extra_applications()
    ]
  end

  defp extra_applications() do
    [:logger, :logger_file_backend]
  end

  # TODO - update to the latest Phoenix and add LiveView

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:logger_file_backend, "~> 0.0.10"},
      {:phoenix, "~> 1.4"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:httpoison, "~> 1.5"},
      {:poison, "~> 4.0"},
      {:elixir_uuid, "~> 1.2"},
      {:gettext, "~> 0.11"},
      {:phoenix_pubsub, "~> 1.0"},
      {:phoenix_html, "~> 2.10"},
      {:cowboy, "~> 1.0"}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
