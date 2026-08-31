defmodule GlobalCombat.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production, without Mix
  (which is not available in a release). Invoked by `rel/overlays/bin/migrate`
  per docs/launch.md §3 ("whoever runs the release ships `mix ecto.migrate` as
  a release step or a one-shot job before the app's first boot").
  """

  @app :global_combat

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
