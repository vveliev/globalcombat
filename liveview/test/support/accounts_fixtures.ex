defmodule GlobalCombat.AccountsFixtures do
  @moduledoc "Test helpers for creating `GlobalCombat.Accounts` entities."

  alias GlobalCombat.Accounts.{Account, Password}
  alias GlobalCombat.Repo

  def unique_account_name, do: "account#{System.unique_integer([:positive])}"
  def unique_account_email, do: "account#{System.unique_integer([:positive])}@example.com"
  def valid_account_password, do: "hunter22"

  def valid_account_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => unique_account_name(),
      "email" => unique_account_email(),
      "password" => valid_account_password(),
      "password_confirmation" => valid_account_password()
    })
  end

  def account_fixture(attrs \\ %{}) do
    {:ok, account} =
      attrs
      |> valid_account_attributes()
      |> GlobalCombat.Accounts.register_account()

    account
  end

  @doc "Inserts an account with a raw (unhashed) `password` column, as every legacy write path did."
  def legacy_plaintext_account_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    password = Map.get(attrs, :password, "plaintextpw")

    %Account{}
    |> Ecto.Changeset.change(%{
      name: Map.get(attrs, :name, unique_account_name()),
      email: Map.get(attrs, :email, unique_account_email()),
      password: password,
      signed_up: DateTime.utc_now(:second),
      opt_out_key: Enum.random(0..999_999)
    })
    |> Repo.insert!()
    |> Map.put(:password, password)
  end

  @doc "Inserts an account whose password is the legacy truncated SHA-512 hash of `password`."
  def legacy_hashed_account_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    password = Map.get(attrs, :password, "oldhashedpw")
    stored = password |> Password.legacy_hash() |> String.slice(0, 30)

    %Account{}
    |> Ecto.Changeset.change(%{
      name: Map.get(attrs, :name, unique_account_name()),
      email: Map.get(attrs, :email, unique_account_email()),
      password: stored,
      signed_up: DateTime.utc_now(:second),
      opt_out_key: Enum.random(0..999_999)
    })
    |> Repo.insert!()
    |> Map.put(:password, password)
  end

  def disable_account!(%Account{} = account) do
    account
    |> Ecto.Changeset.change(%{disabled_by: account.id})
    |> Repo.update!()
  end
end
