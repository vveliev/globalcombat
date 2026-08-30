defmodule GlobalCombat.Repo.Migrations.CreateAccountLogins do
  use Ecto.Migration

  # Legacy `account_login` has a composite (account_id, datetime) primary key and is written
  # with `insert ignore` (docs/schema-map.md §3.2, ADR-0002) to silently de-dup same-second
  # logins. A surrogate `id` PK plus a unique index on (account_id, logged_in_at) gives the
  # same de-dup behavior with normal Ecto ergonomics.
  def change do
    create table(:account_login) do
      add :account_id, references(:account, on_delete: :delete_all), null: false
      add :logged_in_at, :utc_datetime, null: false
      add :ipaddress, :string
      add :browser, :string
      add :adminused, :boolean, null: false, default: false
    end

    create unique_index(:account_login, [:account_id, :logged_in_at])
    create index(:account_login, [:ipaddress])
  end
end
