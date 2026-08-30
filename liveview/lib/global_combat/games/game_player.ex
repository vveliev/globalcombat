defmodule GlobalCombat.Games.GamePlayer do
  @moduledoc """
  Port of the live `gc_games.player` row (docs/schema-map.md §3.9) -- the join between a `games`
  row and the account that holds (or is invited to) a seat in it. `is_invite` distinguishes an
  accepted seat (false, ported from `GameServer.PlayerJoined`) from a pending invite (true,
  ported from `GameServer.PlayerInvited`).
  """

  use Ecto.Schema

  schema "game_players" do
    field :is_invite, :boolean, default: false

    belongs_to :game, GlobalCombat.Games.Game
    belongs_to :account, GlobalCombat.Accounts.Account
  end
end
