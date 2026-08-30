defmodule GlobalCombat.Accounts.AccountLogin do
  use Ecto.Schema
  import Ecto.Changeset

  # Audit trail of every successful login — backs `HomeController.IpAddresses`' reverse
  # IP-to-accounts lookup (multi-account/abuse detection) and `HomeController.PlayerInfo`'s
  # per-account login history. See docs/schema-map.md §3.2 and ADR-0002. Must not be dropped or
  # bypassed when porting `AccountController.SetSession`.
  schema "account_login" do
    belongs_to :account, GlobalCombat.Accounts.Account
    field :logged_in_at, :utc_datetime
    field :ipaddress, :string
    field :browser, :string
    field :adminused, :boolean, default: false
  end

  def changeset(account_login, attrs) do
    account_login
    |> cast(attrs, [:account_id, :logged_in_at, :ipaddress, :browser, :adminused])
    |> validate_required([:account_id, :logged_in_at])
    |> update_change(:browser, fn
      nil -> nil
      browser -> String.slice(browser, 0, 250)
    end)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :logged_in_at])
  end
end
