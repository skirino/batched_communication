defmodule BatchedCommunication.MixProject do
  use Mix.Project

  @github_url "https://github.com/skirino/batched_communication"

  def project() do
    [
      app:               :batched_communication,
      version:           "0.1.3",
      elixir:            "~> 1.6",
      build_embedded:    Mix.env() == :prod,
      start_permanent:   Mix.env() == :prod,
      deps:              deps(),
      description:       "Mostly-transparent batching of remote messages in Erlang/Elixir cluster",
      package:           package(),
      source_url:        @github_url,
      homepage_url:      @github_url,
      test_coverage:     [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
    ]
  end

  def application() do
    [
      extra_applications: [],
      mod: {BatchedCommunication.Application, []},
    ]
  end

  defp deps() do
    [
      {:croma      , "~> 0.9"},
      {:dialyze    , "~> 0.2" , [only: :dev]},
      {:ex_doc     , "~> 0.18", [only: :dev]},
      {:excoveralls, "~> 0.8" , [only: :test]},
    ]
  end

  defp package() do
    [
      files:       ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Shunsuke Kirino"],
      licenses:    ["MIT"],
      links:       %{"GitHub repository" => @github_url},
    ]
  end
end
