defmodule Andy.MixProject do
  use Mix.Project

  @target System.get_env("MIX_TARGET") || "host"

  def project do
    [
      app: :andy,
      version: "0.3.0",
      elixir: "~> 1.8",
      target: @target,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Andy.Application, []},
      extra_applications: extra_applications()
    ]
  end

  defp extra_applications() do
    [:logger, :logger_file_backend]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:logger_file_backend, "~> 0.0.10"},
      {:elixir_uuid, "~> 1.2"},
      {:erl_pengine, "~> 0.1.1"},
      {:hackney, "~> 1.15", override: true}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
