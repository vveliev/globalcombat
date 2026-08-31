defmodule GlobalCombat.Engine.RandomAi do
  @moduledoc """
  Port of `GlobalCombat.Core/RandomAiPlayer.cs` (GIF-28). Unscoped by
  default — same as the original, one `think/1` pass mashes random moves
  across the whole board regardless of area ownership, relying on
  `SetAssigned`/`SetAttack`/`SetTransfer`'s own ownership/adjacency checks
  to silently no-op the invalid ones. That whole-board behavior is required
  for `Harness` (`think/1` with no player number), which diffs Elixir's
  draws against the .NET oracle's own whole-board `RandomAiPlayer.Think`
  turn-by-turn and must stay RNG-lockstep with it. The draw counts
  (12/24/11) and their order matter for that lockstep — verified against the
  source with `grep -c` rather than eyeballed, since an off-by-one here
  desyncs every draw after it.

  GIF-118: live Training Mode play (`Games.Server.run_ai_turns/1`) instead
  calls `think/2` with the Computer seat's player number, which scopes
  `pick_area`'s draw to areas that player owns — so the Computer only ever
  assigns/attacks/transfers using its own territories, the way a real
  player's orders would be constrained, instead of randomly mutating the
  human's areas too. Scoping changes which index a draw resolves to (the
  candidate list is smaller) but not how many draws happen per pass, so it's
  intentionally *not* used by `Harness` — it would desync from the oracle's
  whole-board draws.
  """

  alias GlobalCombat.Engine.{DotnetRandom, Game, MapInfo}

  @doc "Port of `RandomAiPlayer.Think`. `player_number` scopes area picks to that player's own areas (GIF-118); `nil` (default) draws from the whole board, unscoped, matching the oracle."
  def think(%Game{} = game, player_number \\ nil) do
    game
    |> repeat(&random_assignment(&1, player_number), 12)
    |> repeat(&random_attack(&1, player_number), 24)
    |> repeat(&random_transfer(&1, player_number), 11)
  end

  defp repeat(game, fun, n), do: Enum.reduce(1..n, game, fn _, game -> fun.(game) end)

  # RandomAssignment: assign 10 armies to a random area.
  defp random_assignment(game, player_number) do
    {area_number, rng} = pick_area(game, player_number)
    {_amount, game} = Game.set_assigned(%{game | rng: rng}, area_number, 10)
    game
  end

  # RandomTransfer: transfer 20 armies from a random area to a random inbound neighbor.
  defp random_transfer(game, player_number) do
    {area_number, rng} = pick_area(game, player_number)
    {target_number, rng} = pick_inbound(game, area_number, rng)
    {_amount, game} = Game.set_transfer(%{game | rng: rng}, area_number, target_number, 20)
    game
  end

  # RandomAttack: attack from a random area toward a random inbound neighbor with 1000 armies
  # (SetAttack/SetTransfer both clamp this down to `TotalArmies - 1`, so 1000 just means "everything").
  defp random_attack(game, player_number) do
    {area_number, rng} = pick_area(game, player_number)
    {target_number, rng} = pick_inbound(game, area_number, rng)
    {_amount, game} = Game.set_attack(%{game | rng: rng}, area_number, target_number, 1000)
    game
  end

  # `game.Areas[random.Next(game.Areas.Count)]` — Areas is a contiguous 1..N list ordered by
  # number, so a random list index is just `random draw + 1`; no need to materialize the list.
  defp pick_area(game, nil) do
    count = MapInfo.num_areas(game.map_name)
    {index, rng} = DotnetRandom.next(game.rng, count)
    {index + 1, rng}
  end

  # GIF-118: same shape as the unscoped draw above, but over `player_number`'s owned areas only —
  # the candidate list is materialized (unlike the unscoped case) since owned areas aren't a
  # contiguous 1..N range.
  defp pick_area(game, player_number) do
    owned =
      game
      |> Game.areas_in_order()
      |> Enum.filter(&Game.owned_by?(&1, player_number))
      |> Enum.map(& &1.number)

    {index, rng} = DotnetRandom.next(game.rng, length(owned))
    {Enum.at(owned, index), rng}
  end

  # `area.AreaInfo.Inbounds[random.Next(inbounds.Count)]` — a random *inbound* neighbor (an area
  # that links to this one), not an outbound link; see MapInfo.inbounds/2.
  defp pick_inbound(game, area_number, rng) do
    inbounds = MapInfo.inbounds(game.map_name, area_number)
    {index, rng} = DotnetRandom.next(rng, length(inbounds))
    {Enum.at(inbounds, index), rng}
  end
end
