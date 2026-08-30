defmodule GlobalCombat.Accounts.PasswordTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Accounts.Password

  describe "hash_password/1 and verify_password/2" do
    test "a hashed password verifies against the original" do
      hash = Password.hash_password("hunter22")
      assert Password.verify_password("hunter22", hash)
    end

    test "a hashed password does not verify against the wrong password" do
      hash = Password.hash_password("hunter22")
      refute Password.verify_password("wrongpassword", hash)
    end

    test "hashing the same password twice produces different output (random salt)" do
      refute Password.hash_password("hunter22") == Password.hash_password("hunter22")
    end

    test "verify_password/2 rejects a malformed stored value instead of raising" do
      refute Password.verify_password("hunter22", "not-a-hash")
      refute Password.verify_password("hunter22", "")
    end
  end

  describe "legacy_hash/1" do
    test "matches the shape of Web/Lib/UserPage.cs's CalculateHash: Base64(SHA512(pepper <> input))" do
      expected =
        :crypto.hash(:sha512, "s&~D$L{a8_" <> "hunter22")
        |> Base.encode64()

      assert Password.legacy_hash("hunter22") == expected
    end
  end

  describe "legacy_hash_matches?/2" do
    test "matches the full 88-character legacy hash" do
      full = Password.legacy_hash("hunter22")
      assert Password.legacy_hash_matches?("hunter22", full)
    end

    test "matches a hash truncated to fit the legacy varchar(30) column" do
      truncated = Password.legacy_hash("hunter22") |> String.slice(0, 30)
      assert Password.legacy_hash_matches?("hunter22", truncated)
    end

    test "rejects the wrong password" do
      truncated = Password.legacy_hash("hunter22") |> String.slice(0, 30)
      refute Password.legacy_hash_matches?("wrongpassword", truncated)
    end

    test "rejects an empty stored value" do
      refute Password.legacy_hash_matches?("hunter22", "")
    end
  end
end
