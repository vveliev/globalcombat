defmodule GlobalCombat.Engine.Wire do
  @moduledoc """
  Converts between the gRPC wire structs (`GlobalCombat.GrpcHost.*`, generated
  from `proto/game_engine.proto`) and `GlobalCombat.Engine.Game`'s native
  structs, for the differential harness (GIF-28).

  Generated struct fields are the exact PascalCase `[ProtoMember]` names and
  can't be accessed with `struct.Field` dot syntax (an uppercase name after
  `.` parses as an alias, not a field) — same constraint noted in
  `GlobalCombat.GameEngine.Client`, so `Map.fetch!/2` throughout here too.
  """

  alias GlobalCombat.Engine.Game
  alias GlobalCombat.GrpcHost

  @doc "Builds a `GlobalCombat.Engine.Game` from a wire `GlobalCombat.GrpcHost.Game`, with the given (already-seeded) RNG."
  def from_wire_game(%GrpcHost.Game{} = wire, rng) do
    %Game{
      map_name: from_wire_map_name(f(wire, :MapName)),
      rng: rng,
      turn: f(wire, :Turn),
      is_non_random: f(wire, :IsNonRandom),
      reverse_attack_order: f(wire, :ReverseAttackOrder),
      minimum_armies: f(wire, :MinimumArmies),
      is_training: f(wire, :IsTraining),
      ended: f(wire, :Ended),
      areas: Map.new(f(wire, :Areas), fn a -> {f(a, :Number), from_wire_area(a)} end),
      players: Map.new(f(wire, :Players), fn p -> {f(p, :Number), from_wire_player(p)} end)
    }
  end

  defp from_wire_area(a) do
    owner = f(a, :Owner)
    target = f(a, :Target)

    %Game.Area{
      number: f(a, :Number),
      owner_number: owner && f(owner, :Number),
      armies: f(a, :Armies),
      assigned_armies: f(a, :AssignedArmies),
      command: from_wire_command(f(a, :Command)),
      target_number: target && f(target, :Number),
      amount: f(a, :Amount)
    }
  end

  defp from_wire_player(p) do
    %Game.Player{
      number: f(p, :Number),
      account_id: f(p, :AccountId),
      name: f(p, :Name),
      done: f(p, :Done),
      areas: f(p, :Areas),
      armies: f(p, :Armies),
      unassigned_armies: f(p, :UnassignedArmies),
      place: f(p, :Place),
      score: f(p, :Score),
      score_expected: f(p, :ScoreExpected),
      rating: f(p, :Rating),
      rating_change: f(p, :RatingChange)
    }
  end

  @doc "Applies a wire `Assignment` list (from `ThinkResponse`) to a `GlobalCombat.Engine.Game` via `Game.set_assigned/3`, in list order."
  def apply_assignments(game, assignments) do
    Enum.reduce(assignments, game, fn a, game ->
      {_amount, game} = Game.set_assigned(game, f(a, :AreaNumber), f(a, :Amount))
      game
    end)
  end

  @doc "Applies a wire `Order` list (from `ThinkResponse` or hand-built) to a `GlobalCombat.Engine.Game` via `Game.set_attack/4`/`Game.set_transfer/4`, in list order."
  def apply_orders(game, orders) do
    Enum.reduce(orders, game, fn order, game ->
      source = f(order, :SourceAreaNumber)
      target = f(order, :TargetAreaNumber)
      amount = f(order, :Amount)

      {_amount, game} =
        case from_wire_command(f(order, :Command)) do
          :attack -> Game.set_attack(game, source, target, amount)
          :transfer -> Game.set_transfer(game, source, target, amount)
        end

      game
    end)
  end

  @doc "Builds wire `Order` structs from a `GlobalCombat.Engine.Game`'s currently-queued area commands, matching how `GameEngineService.Think` derives its `Orders` — used to diff the Elixir port's own AI decisions against the oracle's."
  def to_wire_orders(game) do
    game
    |> Game.areas_in_order()
    |> Enum.filter(&(&1.command != :none))
    |> Enum.map(fn a ->
      %GrpcHost.Order{
        SourceAreaNumber: a.number,
        TargetAreaNumber: a.target_number,
        Amount: a.amount,
        Command: to_wire_command(a.command)
      }
    end)
  end

  defp from_wire_map_name(:Original), do: :original
  defp from_wire_map_name(:Elements), do: :elements

  defp from_wire_command(:None), do: :none
  defp from_wire_command(:Transfer), do: :transfer
  defp from_wire_command(:Attack), do: :attack

  defp to_wire_command(:none), do: :None
  defp to_wire_command(:transfer), do: :Transfer
  defp to_wire_command(:attack), do: :Attack

  defp f(struct, key), do: Map.fetch!(struct, key)
end
