defmodule GlobalCombat.Games.GamePlayer do
  use Ecto.Schema

  # `gc_games.player` (docs/schema-map.md §3.9) — the join between a live `games` row and the
  # `account` that holds (or is invited to) a seat in it. `is_invite` distinguishes an accepted
  # seat (false, ported from `GameServer.PlayerJoined`) from a pending invite (true, ported
  # from `GameServer.PlayerInvited`).
  schema "game_players" do
    belongs_to :game, GlobalCombat.Games.Game
    belongs_to :account, GlobalCombat.Accounts.Account
    field :is_invite, :boolean, default: false
  end
end
