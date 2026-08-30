defmodule GlobalCombat.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        GlobalCombatWeb.Telemetry,
        GlobalCombat.Repo,
        {DNSCluster, query: Application.get_env(:global_combat, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: GlobalCombat.PubSub},
        GlobalCombat.Presence,
        # One process per live game (GIF-30) - see GlobalCombat.Games.Server.
        {Registry, keys: :unique, name: GlobalCombat.Games.Registry},
        GlobalCombat.Games.Supervisor
      ] ++
        turn_scheduler_child() ++
        [
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

  # Off in :test — a periodic GenServer polling GlobalCombat.Repo outside any test's own
  # Ecto Sandbox ownership would race sandboxed test transactions. See
  # GlobalCombat.Games.TurnScheduler.Resolver's moduledoc for why it's a real, always-correct
  # sweep in every other env even with no resolver configured yet (it logs and skips instead of
  # silently advancing turns).
  defp turn_scheduler_child do
    if Application.get_env(:global_combat, :start_turn_scheduler, true) do
      [GlobalCombat.Games.TurnScheduler]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GlobalCombatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
