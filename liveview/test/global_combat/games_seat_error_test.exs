defmodule GlobalCombat.GamesSeatErrorTest do
  # Not async: seating against a just-deleted game makes InnoDB's foreign key
  # check lock the gap where the game was, and run beside other tests'
  # concurrent game inserts that has deadlocked in CI (MySQL error 1213).
  use GlobalCombat.DataCase, async: false

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Games

  test "seat/2 returns any other failure, not swallowed" do
    account = account_fixture()
    {:ok, game} = Games.create_game(%{status: :new})
    :ok = Games.delete_game(game.id)

    assert {:error, %Ecto.Changeset{errors: [game_id: _]}} = Games.seat(game.id, account.id)
  end
end
