defmodule GlobalCombat.Accounts.Password do
  @moduledoc """
  Password hashing for the ported `account.password` column.

  Algorithm choice and rationale: docs/adr/0002-account-password-migration.md. Short version —
  PBKDF2-HMAC-SHA256 via `:crypto.pbkdf2_hmac/5` (pure BEAM, no C NIF to compile) instead of
  Bcrypt/Argon2, because this port's build environment has no C compiler available. 600_000
  iterations is OWASP's 2023 minimum for PBKDF2-HMAC-SHA256.

  Also carries the legacy hash check from `Web/Lib/UserPage.cs`'s `CalculateHash` (SHA-512 with
  a hardcoded pepper, Base64-encoded, truncated to fit the old `varchar(30)` column) so
  `GlobalCombat.Accounts.authenticate_account/2` can verify against rows written before the
  port without forcing a reset — see ADR-0002.
  """

  @iterations 600_000
  @salt_bytes 16
  @derived_key_bytes 32

  @legacy_pepper "s&~D$L{a8_"

  @doc "Hashes `password`, returning an encoded string safe to store in `account.password`."
  def hash_password(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    hash = :crypto.pbkdf2_hmac(:sha256, password, salt, @iterations, @derived_key_bytes)
    encode(@iterations, salt, hash)
  end

  @doc """
  Verifies `password` against an encoded PBKDF2 hash produced by `hash_password/1`.

  Runs in constant time with respect to the comparison itself; still short-circuits on a
  malformed `encoded` value; that's fine, malformed stored hashes aren't secret.
  """
  def verify_password(password, encoded) when is_binary(password) and is_binary(encoded) do
    with {:ok, iterations, salt, expected} <- decode(encoded) do
      actual = :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, byte_size(expected))
      Plug.Crypto.secure_compare(actual, expected)
    else
      :error -> false
    end
  end

  @doc "The legacy `CalculateHash(password)` from `Web/Lib/UserPage.cs` — SHA-512 + pepper, Base64."
  def legacy_hash(password) when is_binary(password) do
    :crypto.hash(:sha512, @legacy_pepper <> password) |> Base.encode64()
  end

  @doc """
  True if `stored` is a (possibly `varchar(30)`-truncated) prefix of the legacy hash of
  `password` — mirrors `stored == truncate30(CalculateHash(input))` from ADR-0002.
  """
  def legacy_hash_matches?(password, stored) when is_binary(password) and is_binary(stored) do
    full = legacy_hash(password)

    byte_size(stored) > 0 and byte_size(stored) <= byte_size(full) and
      Plug.Crypto.secure_compare(binary_part(full, 0, byte_size(stored)), stored)
  end

  defp encode(iterations, salt, hash) do
    Enum.join(["pbkdf2-sha256", iterations, Base.encode64(salt), Base.encode64(hash)], "$")
  end

  defp decode("pbkdf2-sha256$" <> rest) do
    with [iterations_str, salt_b64, hash_b64] <- String.split(rest, "$"),
         {iterations, ""} <- Integer.parse(iterations_str),
         {:ok, salt} <- Base.decode64(salt_b64),
         {:ok, hash} <- Base.decode64(hash_b64) do
      {:ok, iterations, salt, hash}
    else
      _ -> :error
    end
  end

  defp decode(_), do: :error
end
