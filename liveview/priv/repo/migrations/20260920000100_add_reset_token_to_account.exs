defmodule GlobalCombat.Repo.Migrations.AddResetTokenToAccount do
  use Ecto.Migration

  def change do
    alter table(:account) do
      add :reset_token_hash, :string
      add :reset_token_expires_at, :utc_datetime
    end

    create index(:account, [:reset_token_hash])
  end
end
