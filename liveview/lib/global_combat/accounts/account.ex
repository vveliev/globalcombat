defmodule GlobalCombat.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  alias GlobalCombat.Accounts.Password

  # Value/mapping decisions: docs/schema-map.md §2.3, §2.4, §3.1 (GIF-26/GIF-29). `status` and
  # `forward_emails` preserve the exact legacy strings (including the `Comissioned` typo) since
  # those are the literal values already on disk in the source app; see the schema-map for why.
  @statuses [
    civilian: "Civilian",
    enlisted: "Enlisted",
    comissioned: "Comissioned",
    admin: "Admin",
    super_admin: "SuperAdmin",
    discharged: "Discharged",
    disabled: "Disabled"
  ]

  @forward_email_settings [
    game_starts: "GameStarts",
    all_game: "AllGame",
    all: "All",
    none: "None",
    game_all: "GameAll"
  ]

  schema "account" do
    field :name, :string
    field :password, :string, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :email, :string

    field :info_visible, :boolean, default: true
    field :wins, :integer, default: 0
    field :games, :integer, default: 0
    field :last_on, :utc_datetime
    field :num_logins, :integer, default: 0
    field :last_ip, :string
    field :signed_up, :utc_datetime

    field :status, Ecto.Enum, values: @statuses, default: :civilian
    field :forward_emails, Ecto.Enum, values: @forward_email_settings, default: :all

    belongs_to :disabled_by_account, __MODULE__, foreign_key: :disabled_by
    belongs_to :referrer, __MODULE__, foreign_key: :referred_by

    field :opt_out, :boolean, default: false
    field :opt_out_key, :integer

    field :rating, :integer, default: 8500
    field :admin, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  Registration changeset — mirrors `BaseController.CreateAccount`'s validation
  (`Web/Controllers/BaseController.cs:153`): valid email, non-empty trimmed login name,
  matching password confirmation, five-character password floor (ADR-0002 carries this floor
  forward unchanged). Hashes the password immediately with `Password.hash_password/1` — unlike
  the legacy write path, new registrations never touch plaintext storage.
  """
  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :email, :password, :password_confirmation, :referred_by])
    |> validate_required([:name, :email, :password])
    |> update_change(:name, &String.trim/1)
    |> update_change(:email, &String.trim/1)
    |> validate_length(:name, min: 1, max: 30)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 255)
    |> validate_length(:password, min: 5, max: 72, message: "must be at least five letters")
    |> validate_confirmation(:password,
      required: true,
      message: "the passwords you entered do not match"
    )
    |> unsafe_validate_unique(:name, GlobalCombat.Repo, message: "Login name already taken")
    |> unique_constraint(:name, message: "Login name already taken")
    |> unsafe_validate_unique(:email, GlobalCombat.Repo,
      message: "There is already an account with that email address."
    )
    |> unique_constraint(:email, message: "There is already an account with that email address.")
    |> put_password_hash()
    |> put_change(:opt_out_key, Enum.random(0..999_999))
    |> put_change(:signed_up, DateTime.utc_now(:second))
  end

  @doc "Sets `password` to `hash_password(new_password)` — used for changes, resets, and rehash-on-login."
  def password_changeset(account, new_password) do
    account
    |> cast(%{password: new_password}, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 5, max: 72, message: "must be at least five letters")
    # `cast/3` only records a field as "changed" when the new value differs from the current
    # one — but the whole point of rehash-on-login (ADR-0002) is to replace a *matching*
    # legacy plaintext value with its hash, where `new_password` often equals the current raw
    # `account.password` verbatim. Without `force_change`, `put_password_hash/1` below would
    # see no change and silently skip hashing, leaving the row plaintext forever.
    |> force_change(:password, new_password)
    |> put_password_hash()
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password, Password.hash_password(password))
    end
  end

  @doc """
  Ports `Account.Rank` (`Web/Models/Account.cs:36-52`) — the rank ladder is purely a function
  of `rating`, so this must match the C# thresholds exactly for Stats/PlayerInfo/Index to show
  the same rank as the legacy site for any given rating (GIF-33's "Elo figures must match"
  bar). Boundary values are cross-checked against an independently-written reimplementation in
  `GlobalCombat.AccountTest` (differential-harness style, per GIF-28's precedent), not just
  eyeballed against this function.
  """
  def rank(%__MODULE__{rating: rating}), do: rank(rating)

  def rank(rating) when is_integer(rating) do
    cond do
      rating < 8400 -> "Private"
      rating < 8750 -> "Private First Class"
      rating < 9100 -> "Corporal"
      rating < 9500 -> "Sergeant"
      rating < 10000 -> "Major"
      true -> "General"
    end
  end
end
