defmodule MLApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ml_app,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {MLApp, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:dala, path: "../../"},
      # ML dependencies - automatically included!
      {:nx, github: "elixir-nx/nx", sparse: "nx"},
      {:emlx, github: "elixir-nx/emlx", branch: "main"},
      {:axon, "~> 0.6"}
    ]
  end
end
