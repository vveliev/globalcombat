defmodule GlobalCombat.Engine.RandomAi do
  @moduledoc """
  Port of `GlobalCombat.Core/RandomAiPlayer.cs` (GIF-28). Not player-scoped —
  same as the original, one `think/1` pass mashes random moves across the
  whole board regardless of area ownership, relying on `SetAssigned`/
  `SetAttack`/`SetTransfer`'s own ownership/adjacency checks to silently
  no-op the invalid ones. The draw counts (12/24/11) and their order matter
  for RNG-lockstep with the oracle — verified against the source with
  `grep -c` rather than eyeballed, since an off-by-one here desyncs every
  draw after it.
  """

  alias GlobalCombat.Engine.{DotnetRandom, Game, MapInfo}

  @doc "Port of `RandomAiPlayer.Think`."
  def think(%Game{} = game) do
    game
    |> repeat(&random_assignment/1, 12)
    |> repeat(&random_attack/1, 24)
    |> repeat(&random_transfer/1, 11)
  end

  defp repeat(game, fun, n), do: Enum.reduce(1..n, game, fn _, game -> fun.(game) end)

  # RandomAssignment: assign 10 armies to a random area.
  defp random_assignment(game) do
    {area_number, rng} = pick_area(game)
    {_amount, game} = Game.set_assigned(%{game | rng: rng}, area_number, 10)
    game
  end

  # RandomTransfer: transfer 20 armies from a random area to a random inbound neighbor.
  defp random_transfer(game) do
    {area_number, rng} = pick_area(game)
    {target_number, rng} = pick_inbound(game, area_number, rng)
    {_amount, game} = Game.set_transfer(%{game | rng: rng}, area_number, target_number, 20)
    game
  end

  # RandomAttack: attack from a random area toward a random inbound neighbor with 1000 armies
  # (SetAttack/SetTransfer both clamp this down to `TotalArmies - 1`, so 1000 just means "everything").
  defp random_attack(game) do
    {area_number, rng} = pick_area(game)
    {target_number, rng} = pick_inbound(game, area_number, rng)
    {_amount, game} = Game.set_attack(%{game | rng: rng}, area_number, target_number, 1000)
    game
  end

  # `game.Areas[random.Next(game.Areas.Count)]` — Areas is a contiguous 1..N list ordered by
  # number, so a random list index is just `random draw + 1`; no need to materialize the list.
  defp pick_area(game) do
    count = MapInfo.num_areas(game.map_name)
    {index, rng} = DotnetRandom.next(game.rng, count)
    {index + 1, rng}
  end

  # `area.AreaInfo.Inbounds[random.Next(inbounds.Count)]` — a random *inbound* neighbor (an area
  # that links to this one), not an outbound link; see MapInfo.inbounds/2.
  defp pick_inbound(game, area_number, rng) do
    inbounds = MapInfo.inbounds(game.map_name, area_number)
    {index, rng} = DotnetRandom.next(rng, length(inbounds))
    {Enum.at(inbounds, index), rng}
  end
end
