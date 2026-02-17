defmodule RepomaticApt.MixProject do
  use Mix.Project

  def project do
    [
      app: :repomatic_apt,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {RepomaticApt.Application, []}
    ]
  end

  defp releases do
    [
      repomatic_apt: [
        include_executables_for: [:unix]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:ezstd, "~> 1.2"},
      {:xz, "~> 0.4"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
