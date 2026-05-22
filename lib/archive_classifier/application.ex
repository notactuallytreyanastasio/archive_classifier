defmodule ArchiveClassifier.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ArchiveClassifierWeb.Telemetry,
        ArchiveClassifier.Repo,
        ArchiveClassifier.Cache
      ] ++
        maybe_whisper() ++
        [
          {DNSCluster, query: Application.get_env(:archive_classifier, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: ArchiveClassifier.PubSub},
          ArchiveClassifierWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ArchiveClassifier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_whisper do
    if Application.get_env(:archive_classifier, :start_whisper, false) do
      [ArchiveClassifier.ML.Whisper]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ArchiveClassifierWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
