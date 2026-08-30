defmodule GlobalCombat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  # Column shape follows docs/schema-map.md §3.7 (GIF-26/GIF-33). `to_id`/`from_id` are
  # deliberately plain integers, not `references/belongs_to` FKs: `GameServer.OnMessage`
  # writes `-game.Id` as a sentinel recipient for game-forum broadcasts
  # (`Web/Models/GameServer.cs:48`), and account id `1` is the reserved System account — a real
  # FK constraint would reject both conventions.
  def change do
    create table(:message) do
      add :to_id, :integer, null: false
      add :from_id, :integer, null: false
      add :sent_at, :utc_datetime, null: false
      add :text, :text, null: false
      add :read, :boolean, null: false, default: false
      add :deleted, :boolean, null: false, default: false
    end

    create index(:message, [:to_id])
    create index(:message, [:from_id])
  end
end
