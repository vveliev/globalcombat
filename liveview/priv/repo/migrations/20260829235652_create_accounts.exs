defmodule GlobalCombat.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  # Column shape follows docs/schema-map.md §2.3/§2.4/§3.1 (GIF-26/GIF-29). This creates the
  # target post-port shape for a fresh dev/test database; migrating a real legacy
  # `globalcombat.account` table's existing rows into this shape (ALTER TABLE, not CREATE
  # TABLE) is a separate, not-yet-scoped deployment task.
  #
  # Columns dropped rather than carried forward, per the schema-map's "dead" findings:
  #   - cc_info / visible_cc_info: zero code references, possible PCI-sensitive historical
  #     data — flagged for Dev, not dropped from the live DB, just not modeled here.
  #   - session_id / session_exp: commented out in Account.Load; session identity lives in
  #     the auth session, not these columns.
  def change do
    create table(:account) do
      add :name, :string, null: false
      add :password, :text, null: false
      add :email, :string, null: false

      add :info_visible, :boolean, null: false, default: true
      add :wins, :integer, null: false, default: 0
      add :games, :integer, null: false, default: 0
      add :last_on, :utc_datetime
      add :num_logins, :integer, null: false, default: 0
      add :last_ip, :string
      add :signed_up, :utc_datetime

      add :status, :string, null: false, default: "Civilian"
      add :forward_emails, :string, null: false, default: "All"

      # disabled_by/referred_by are dual-purpose in the legacy schema (flag + audit trail /
      # capability value + who-referred-whom) — modeled here as nullable self-referential FKs
      # per the schema-map's "worth doing during the port" note, nil meaning "not disabled" /
      # "no referrer" instead of the legacy sentinel `0`.
      add :disabled_by, references(:account, on_delete: :nilify_all)
      add :referred_by, references(:account, on_delete: :nilify_all)

      add :opt_out, :boolean, null: false, default: false
      add :opt_out_key, :integer

      add :rating, :integer, null: false, default: 8500
      add :admin, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:account, [:name])
    create unique_index(:account, [:email])
  end
end
