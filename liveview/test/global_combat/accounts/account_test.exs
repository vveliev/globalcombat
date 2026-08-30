defmodule GlobalCombat.Accounts.AccountTest do
  @moduledoc """
  Verifies `Account.rank/1` against the legacy `Account.Rank` C# property
  (`Web/Models/Account.cs:36-52`) — this is the GIF-33 "Elo figures for a sample of players
  match the current site" check for Stats/PlayerInfo's Rating/Rank columns.

  Why a rank/rating comparison, not a live Elo *computation* comparison: the rating number
  itself isn't computed by either app at render time — it's the stored `account.rating`
  column, written once, at game-end, by `GameServer.OnEnd`'s
  `update account set rating = rating + <RatingChange>` (the Elo math itself already has a
  bit-for-bit differential harness against the .NET engine, see
  `GlobalCombat.Engine.Game`/`GlobalCombat.Engine.Harness`, GIF-28). Both apps read the same
  MySQL `account.rating` column with zero transformation, so they trivially agree on the
  number *by construction* — there is no independent Elixir-side computation to diverge. The
  one piece of display logic that genuinely reads `rating` and derives something from it is
  the `Rank` ladder, so that's what this test differentially verifies, the same way GIF-28's
  harness verifies engine logic: by re-deriving the expected answer from an independent
  implementation, not by calling the code under test twice.

  This also could not be checked against the live production site by request/response
  comparison — globalcombat.com no longer serves the game (parked domain, confirmed
  2026-08-29, see GIF-34) — so "matches the current site" is verified against the legacy
  source (`Web/Models/Account.cs`), not a live HTTP round trip.
  """

  use GlobalCombat.DataCase, async: true

  import GlobalCombat.AccountsFixtures

  alias GlobalCombat.Accounts.Account
  alias GlobalCombat.Repo

  # Independent reimplementation of `Web/Models/Account.cs:36-52`'s `Rank` getter, transcribed
  # separately from `Account.rank/1` (not calling it) so this test can't pass merely by
  # asserting a function against itself.
  defp legacy_rank(rating) do
    cond do
      rating < 8400 -> "Private"
      rating < 8750 -> "Private First Class"
      rating < 9100 -> "Corporal"
      rating < 9500 -> "Sergeant"
      rating < 10000 -> "Major"
      true -> "General"
    end
  end

  describe "rank/1 boundary values" do
    # Every threshold boundary the C# `if (Rating < N)` chain can land on, both sides of each
    # cutoff, cross-checked against `legacy_rank/1` above.
    @boundaries [
      0,
      8399,
      8400,
      8401,
      8749,
      8750,
      8751,
      9099,
      9100,
      9101,
      9499,
      9500,
      9501,
      9999,
      10000,
      10001,
      20_000
    ]

    test "matches the independent reimplementation at every boundary" do
      for rating <- @boundaries do
        assert Account.rank(rating) == legacy_rank(rating),
               "rank(#{rating}) = #{Account.rank(rating)}, expected #{legacy_rank(rating)}"
      end
    end

    test "the documented default rating (8500) is Private First Class" do
      assert Account.rank(8500) == "Private First Class"
    end
  end

  describe "sample-of-players verification (GIF-33 done-when criterion)" do
    # Sample size: 7 accounts, one per rank tier plus one duplicate-tier check, ratings chosen
    # to land inside every tier `Account.cs`'s ladder defines (not just at boundaries — the
    # boundary test above already covers those exhaustively).
    @sample [
      {"sample_private", 8000},
      {"sample_pfc", 8500},
      {"sample_corporal", 8900},
      {"sample_sergeant", 9300},
      {"sample_major", 9700},
      {"sample_general", 10_500},
      {"sample_general_2", 50_000}
    ]

    test "account.rating read straight from the DB (as Stats/PlayerInfo render it) matches the legacy Rank ladder for a 7-account sample" do
      accounts =
        for {name, rating} <- @sample do
          account_fixture(%{"name" => name})
          |> Ecto.Changeset.change(rating: rating)
          |> Repo.update!()
        end

      # Query: the exact lookup `HomeController.PlayerInfo`/`Stats` would issue per account —
      # `Repo.get(Account, id)`, i.e. `select * from account where id = <id>` — then the same
      # `rating`/`rank(rating)` pair `home_html/player_info.html.heex` renders into the
      # "Rating"/"Rank" stat cards.
      results =
        for account <- accounts do
          reloaded = Repo.get!(Account, account.id)
          {reloaded.name, reloaded.rating, Account.rank(reloaded.rating)}
        end

      # Output (captured 2026-08-30, this test run):
      #   {"sample_private", 8000, "Private"}
      #   {"sample_pfc", 8500, "Private First Class"}
      #   {"sample_corporal", 8900, "Corporal"}
      #   {"sample_sergeant", 9300, "Sergeant"}
      #   {"sample_major", 9700, "Major"}
      #   {"sample_general", 10500, "General"}
      #   {"sample_general_2", 50000, "General"}
      expected = for {name, rating} <- @sample, do: {name, rating, legacy_rank(rating)}

      assert results == expected
    end
  end
end
