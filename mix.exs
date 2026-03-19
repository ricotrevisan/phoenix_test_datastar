defmodule PhoenixTestDatastar.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_test_datastar,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "PhoenixTestDatastar",
      description: "A PhoenixTest driver for Dstar-powered Phoenix applications"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_test, "~> 0.10"},
      {:phoenix, "~> 1.7"},
      {:plug, "~> 1.15"},
      {:jason, "~> 1.4"},
      {:floki, "~> 0.36"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end
end
