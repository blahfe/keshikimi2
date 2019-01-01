defmodule Keshikimi2.MixProject do
  use Mix.Project

  def project do
    [
      app: :keshikimi2,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Keshikimi2.Application, [Default]}
    ]
  end

  defp deps do
    [
      {:cachex, "~> 3.1"},
      {:deps_ghq_get, "~> 0.1.2", only: :dev},
      {:floki, "~> 0.20.0"},
      {:httpoison, "~> 1.4"},
      {:httpoison_form_data, "~> 0.1.3"},
      {:poison, "~> 3.1"},
      {:timex, "~> 3.1"},
      {:yaml_elixir, "~> 2.1.0"}
    ]
  end

  defp aliases do
    [
      "deps.get": ["deps.get", "deps.ghq_get --async"]
    ]
  end
end
