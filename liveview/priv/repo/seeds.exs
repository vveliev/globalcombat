# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# GIF-29: seeds a handful of `account` rows in the legacy password shapes ADR-0002 describes,
# so `authenticate_account/2`'s three-way match (bcrypt-of-old-hash-format / legacy SHA-512 /
# plaintext) can be exercised against a real database, not just fixtures inlined in tests.

alias GlobalCombat.Accounts.{Account, Password}
alias GlobalCombat.Repo

# A modern account, registered after the port — password is already hashed on write.
{:ok, _modern} =
  GlobalCombat.Accounts.register_account(%{
    "name" => "modern_player",
    "email" => "modern_player@example.com",
    "password" => "correcthorse",
    "password_confirmation" => "correcthorse"
  })

# A pre-port account whose password was never hashed at all — the common case per ADR-0002
# (registration/change-password/reset all wrote plaintext in the legacy app).
%Account{}
|> Ecto.Changeset.change(%{
  name: "legacy_plaintext",
  email: "legacy_plaintext@example.com",
  password: "plaintextpw",
  signed_up: DateTime.utc_now(:second),
  opt_out_key: Enum.random(0..999_999)
})
|> Repo.insert!()

# A pre-port account whose password went through `UserPage<int>.CalculateHash` and got
# truncated to fit the old `varchar(30)` column.
legacy_hash = Password.legacy_hash("oldhashedpw") |> String.slice(0, 30)

%Account{}
|> Ecto.Changeset.change(%{
  name: "legacy_hashed",
  email: "legacy_hashed@example.com",
  password: legacy_hash,
  signed_up: DateTime.utc_now(:second),
  opt_out_key: Enum.random(0..999_999)
})
|> Repo.insert!()

# A disabled account — logging in must be blocked regardless of password shape.
disabled_owner =
  %Account{}
  |> Ecto.Changeset.change(%{
    name: "legacy_disabled",
    email: "legacy_disabled@example.com",
    password: "whatever_pw",
    signed_up: DateTime.utc_now(:second),
    opt_out_key: Enum.random(0..999_999)
  })
  |> Repo.insert!()

disabled_owner
|> Ecto.Changeset.change(%{disabled_by: disabled_owner.id})
|> Repo.update!()

IO.puts("""
Seeded accounts:
  modern_player     / correcthorse   (already PBKDF2-hashed)
  legacy_plaintext  / plaintextpw    (plaintext row — rehashes to PBKDF2 on first login)
  legacy_hashed     / oldhashedpw    (truncated legacy SHA-512 hash — rehashes on first login)
  legacy_disabled   / whatever_pw    (disabled — login is blocked)
""")
