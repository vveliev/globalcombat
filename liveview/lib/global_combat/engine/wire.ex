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

  @doc """
  Builds a wire `GlobalCombat.GrpcHost.Game` from a `GlobalCombat.Engine.Game` plus the
  `GlobalCombat.Games.Server`-only config wrapping it (`:game_id`, `:turn_length_minutes`,
  `:max_players`, `:is_fogged`) — for persisting live play state to `games.serialized` between
  turns (GIF-74). Reuses the same wire format `GlobalCombat.Games.GameSummary` already decodes
  for the tourney flow (GIF-33), so a `games` row's `serialized` blob means the same thing
  regardless of which flow wrote it.

  RNG state has no wire representation (the .NET oracle owns its `System.Random` internally and
  never puts it on the wire) and is intentionally not round-tripped here: a game rehydrated from
  this blob after a process restart continues with a freshly reseeded RNG, not the oracle's
  matching stream — fine for production play (any valid seed is a fair game), but this blob must
  never be fed into the differential harness expecting bit-exact continuation.
  """
  def to_wire_game(%Game{} = game, opts) do
    %GrpcHost.Game{
      Id: Keyword.fetch!(opts, :game_id),
      GameName: "",
      MapName: to_wire_map_name(game.map_name),
      TurnLength: Keyword.fetch!(opts, :turn_length_minutes),
      MaxPlayers: Keyword.fetch!(opts, :max_players),
      IsFogged: Keyword.fetch!(opts, :is_fogged),
      IsNonRandom: game.is_non_random,
      ReverseAttackOrder: game.reverse_attack_order,
      MinimumArmies: game.minimum_armies,
      Turn: game.turn,
      Started: true,
      Ended: game.ended,
      Areas: Enum.map(Game.areas_in_order(game), &to_wire_area/1),
      Players: Enum.map(Game.players_in_order(game), &to_wire_player/1),
      IsPrivate: Keyword.get(opts, :is_private, false),
      IsTraining: game.is_training,
      TourneyId: 0
    }
  end

  defp to_wire_area(%Game.Area{} = a) do
    %GrpcHost.Area{
      Number: a.number,
      Owner: a.owner_number && %GrpcHost.Player{Number: a.owner_number},
      Armies: a.armies,
      AssignedArmies: a.assigned_armies,
      Command: to_wire_command(a.command),
      Target: a.target_number && %GrpcHost.Area{Number: a.target_number},
      Amount: a.amount
    }
  end

  defp to_wire_player(%Game.Player{} = p) do
    %GrpcHost.Player{
      AccountId: p.account_id,
      Number: p.number,
      Name: p.name,
      Done: p.done,
      Areas: p.areas,
      Armies: p.armies,
      UnassignedArmies: p.unassigned_armies,
      Place: p.place,
      Score: p.score,
      ScoreExpected: p.score_expected,
      Rating: p.rating,
      RatingChange: p.rating_change
    }
  end

  @doc """
  Reverse of `to_wire_game/2`: decodes a persisted wire `GlobalCombat.GrpcHost.Game` back into
  a `%{engine: %GlobalCombat.Engine.Game{}, is_fogged: boolean, max_players: integer}` — the full
  set `GlobalCombat.Games.Server` needs to rehydrate after a process/node restart (GIF-74), not
  just the engine struct `from_wire_game/2` alone builds (that's also used by the differential
  harness, which never needs `is_fogged`/`max_players` — Server-only config, not engine state).
  """
  def from_wire_snapshot(%GrpcHost.Game{} = wire, rng) do
    %{
      engine: from_wire_game(wire, rng),
      is_fogged: f(wire, :IsFogged),
      max_players: f(wire, :MaxPlayers)
    }
  end

  @doc """
  Snapshot of a not-yet-started lobby as a wire `GlobalCombat.GrpcHost.Game` with `Started:
  false` — what `GlobalCombat.Games.Server` persists on every roster change so a lobby survives
  its process dying (a dev-server restart, a deploy, a crash) exactly the way a started game
  already does through `to_wire_game/2`. Mirrors `GameServer.PlayerJoined`/`PlayerInvited` in
  the original, which called `SaveGame` (the same blob) before the game ever started.

  Takes any map with the lobby fields below — in practice the `%GlobalCombat.Games.Server{}`
  state itself, so the two never drift. `players` is the server's roster shape,
  `[{number, %{account_id: _, name: _}}]`; `invites` is `[%{account_id: _, name: _}]`. Areas are
  empty: they are dealt by `Games.Server.new_engine/1` at start, never before.
  """
  def to_wire_lobby(
        %{
          game_id: game_id,
          map_name: map_name,
          turn_length_minutes: turn_length_minutes,
          max_players: max_players,
          is_fogged: is_fogged,
          is_non_random: is_non_random,
          reverse_attack_order: reverse_attack_order,
          minimum_armies: minimum_armies,
          is_private: is_private,
          is_training: is_training,
          players: players,
          invites: invites
        } = _lobby
      ) do
    %GrpcHost.Game{
      Id: game_id,
      GameName: "",
      MapName: to_wire_map_name(map_name),
      TurnLength: turn_length_minutes,
      MaxPlayers: max_players,
      IsFogged: is_fogged,
      IsNonRandom: is_non_random,
      ReverseAttackOrder: reverse_attack_order,
      MinimumArmies: minimum_armies,
      Turn: 1,
      Started: false,
      Ended: false,
      Areas: [],
      Players:
        Enum.map(players, fn {number, p} ->
          %GrpcHost.Player{Number: number, AccountId: p.account_id, Name: p.name}
        end),
      IsPrivate: is_private,
      IsTraining: is_training,
      Invites:
        Enum.map(invites, fn i -> %GrpcHost.Invite{AccountId: i.account_id, Name: i.name} end),
      TourneyId: 0
    }
  end

  @doc "Whether a persisted wire game has been started — `false` means `from_wire_lobby/1` applies, `true` means `from_wire_snapshot/2` does."
  def started?(%GrpcHost.Game{} = wire), do: f(wire, :Started)

  @doc """
  Reverse of `to_wire_lobby/1`: the lobby-state fields `GlobalCombat.Games.Server` needs to
  come back up as a `:lobby` with the same roster, pending invites and ruleset — keyed exactly
  like the `%Games.Server{}` fields so the server can `struct/2` them straight in.
  """
  def from_wire_lobby(%GrpcHost.Game{} = wire) do
    %{
      map_name: from_wire_map_name(f(wire, :MapName)),
      is_fogged: f(wire, :IsFogged),
      is_training: f(wire, :IsTraining),
      is_non_random: f(wire, :IsNonRandom),
      reverse_attack_order: f(wire, :ReverseAttackOrder),
      minimum_armies: f(wire, :MinimumArmies),
      max_players: f(wire, :MaxPlayers),
      is_private: f(wire, :IsPrivate),
      players:
        wire
        |> f(:Players)
        |> Enum.sort_by(&f(&1, :Number))
        |> Enum.map(fn p ->
          {f(p, :Number), %{account_id: f(p, :AccountId), name: f(p, :Name)}}
        end),
      invites:
        Enum.map(f(wire, :Invites), fn i -> %{account_id: f(i, :AccountId), name: f(i, :Name)} end)
    }
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

  defp to_wire_map_name(:original), do: :Original
  defp to_wire_map_name(:elements), do: :Elements

  defp from_wire_command(:None), do: :none
  defp from_wire_command(:Transfer), do: :transfer
  defp from_wire_command(:Attack), do: :attack

  defp to_wire_command(:none), do: :None
  defp to_wire_command(:transfer), do: :Transfer
  defp to_wire_command(:attack), do: :Attack

  defp f(struct, key), do: Map.fetch!(struct, key)
end
