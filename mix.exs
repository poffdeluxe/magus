defmodule Magus.MixProject do
  use Mix.Project

  def project do
    [
      app: :magus,
      name: "Magus",
      description: "A very simple library for implementing graph-based LLM agents in Elixir",
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/poffdeluxe/magus"
      }
    ]
  end

  defp deps do
    [
      {:ex_json_schema, "~> 0.10.2"},
      {:langchain, "~> 0.3.0-rc.0"},
      {:libgraph, "~> 0.16.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:retry, "~> 0.18"}
    ]
  end
end
