defmodule GlobalCombat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GlobalCombatWeb.Telemetry,
      GlobalCombat.Repo,
      {DNSCluster, query: Application.get_env(:global_combat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GlobalCombat.PubSub},
      # Start a worker by calling: GlobalCombat.Worker.start_link(arg)
      # {GlobalCombat.Worker, arg},
      # Start to serve requests, typically the last entry
      GlobalCombatWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GlobalCombat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GlobalCombatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
