defmodule GlobalCombat.AccountsTest do
  use GlobalCombat.DataCase, async: true

  alias GlobalCombat.Accounts
  alias GlobalCombat.Accounts.AccountLogin

  import GlobalCombat.AccountsFixtures

  describe "register_account/1" do
    test "registers an account with a hashed password" do
      attrs = valid_account_attributes()
      assert {:ok, account} = Accounts.register_account(attrs)
      assert account.name == attrs["name"]
      assert account.email == attrs["email"]
      assert String.starts_with?(account.password, "pbkdf2-sha256$")
    end

    test "requires a matching password confirmation" do
      attrs = valid_account_attributes(%{"password_confirmation" => "somethingelse"})
      assert {:error, changeset} = Accounts.register_account(attrs)

      assert "the passwords you entered do not match" in errors_on(changeset).password_confirmation
    end

    test "requires at least five characters" do
      attrs = valid_account_attributes(%{"password" => "ab", "password_confirmation" => "ab"})
      assert {:error, changeset} = Accounts.register_account(attrs)
      assert "must be at least five letters" in errors_on(changeset).password
    end

    test "rejects a duplicate login name" do
      existing = account_fixture()
      attrs = valid_account_attributes(%{"name" => existing.name})
      assert {:error, changeset} = Accounts.register_account(attrs)
      assert "Login name already taken" in errors_on(changeset).name
    end

    test "rejects a duplicate email address" do
      existing = account_fixture()
      attrs = valid_account_attributes(%{"email" => existing.email})
      assert {:error, changeset} = Accounts.register_account(attrs)
      assert "There is already an account with that email address." in errors_on(changeset).email
    end
  end

  describe "authenticate_account/2" do
    test "succeeds for a modern (already-hashed) account with the right password" do
      account = account_fixture()

      assert {:ok, authenticated} =
               Accounts.authenticate_account(account.name, valid_account_password())

      assert authenticated.id == account.id
    end

    test "also accepts login by email address" do
      account = account_fixture()
      assert {:ok, _} = Accounts.authenticate_account(account.email, valid_account_password())
    end

    test "rejects the wrong password" do
      account = account_fixture()

      assert {:error, :bad_password} =
               Accounts.authenticate_account(account.name, "wrongpassword")
    end

    test "rejects an unknown login" do
      assert {:error, :not_found} = Accounts.authenticate_account("nobody-here", "whatever1")
    end

    test "rejects a disabled account, even with the correct password" do
      account = legacy_plaintext_account_fixture()
      disable_account!(account)
      assert {:error, :disabled} = Accounts.authenticate_account(account.name, account.password)
    end

    test "accepts a legacy plaintext row and rehashes it to PBKDF2 on success" do
      account = legacy_plaintext_account_fixture(password: "plaintextpw")

      assert {:ok, authenticated} = Accounts.authenticate_account(account.name, "plaintextpw")
      assert String.starts_with?(authenticated.password, "pbkdf2-sha256$")

      # and the account can still log in afterwards, now via the PBKDF2 branch
      assert {:ok, _} = Accounts.authenticate_account(account.name, "plaintextpw")
    end

    test "accepts a legacy truncated SHA-512 hash and rehashes it to PBKDF2 on success" do
      account = legacy_hashed_account_fixture(password: "oldhashedpw")

      assert {:ok, authenticated} = Accounts.authenticate_account(account.name, "oldhashedpw")
      assert String.starts_with?(authenticated.password, "pbkdf2-sha256$")

      assert {:ok, _} = Accounts.authenticate_account(account.name, "oldhashedpw")
    end

    test "rejects the wrong password against a legacy plaintext row" do
      account = legacy_plaintext_account_fixture(password: "plaintextpw")

      assert {:error, :bad_password} =
               Accounts.authenticate_account(account.name, "wrongpassword")
    end
  end

  describe "record_login/2" do
    test "bumps num_logins, sets last_on, and writes an account_login row" do
      account = account_fixture()
      assert account.num_logins == 0

      assert {:ok, updated} =
               Accounts.record_login(account,
                 ip_address: "203.0.113.5",
                 user_agent: "TestAgent/1.0"
               )

      assert updated.num_logins == 1
      assert updated.last_on

      login = Repo.get_by!(AccountLogin, account_id: account.id)
      assert login.ipaddress == "203.0.113.5"
      assert login.browser == "TestAgent/1.0"
      refute login.adminused
    end

    test "does not blow up when called twice in the same second (insert ignore semantics)" do
      account = account_fixture()

      assert {:ok, _} = Accounts.record_login(account, ip_address: "203.0.113.5")
      assert {:ok, _} = Accounts.record_login(account, ip_address: "203.0.113.5")
    end
  end

  describe "reset_password/1" do
    test "generates a new password, hashes it, and never writes it in cleartext" do
      account = account_fixture()

      assert {:ok, updated, new_password} = Accounts.reset_password(account.name)
      assert byte_size(new_password) == 8
      assert String.starts_with?(updated.password, "pbkdf2-sha256$")
      refute updated.password == new_password

      assert {:ok, _} = Accounts.authenticate_account(account.name, new_password)
    end

    test "returns an error for an unknown login" do
      assert {:error, :not_found} = Accounts.reset_password("nobody-here")
    end
  end

  describe "change_password/3" do
    test "changes the password when the old password is correct" do
      account = account_fixture()

      assert {:ok, updated} =
               Accounts.change_password(account, valid_account_password(), "newpassword1")

      assert {:ok, _} = Accounts.authenticate_account(account.name, "newpassword1")
      assert updated.password != account.password
    end

    test "rejects the wrong old password" do
      account = account_fixture()

      assert {:error, :bad_old_password} =
               Accounts.change_password(account, "wrongoldpassword", "newpassword1")

      assert {:ok, _} = Accounts.authenticate_account(account.name, valid_account_password())
    end

    test "works against a legacy plaintext row's old password too" do
      account = legacy_plaintext_account_fixture(password: "plaintextpw")

      assert {:ok, _updated} = Accounts.change_password(account, "plaintextpw", "newpassword1")
      assert {:ok, _} = Accounts.authenticate_account(account.name, "newpassword1")
    end
  end
end
