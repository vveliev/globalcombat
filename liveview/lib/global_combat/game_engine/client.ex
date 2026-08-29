defmodule GlobalCombat.GameEngine.Client do
  @moduledoc """
  gRPC client for the GlobalCombat.GrpcHost spike service. Generated modules
  live in lib/global_combat/game_engine_pb/, produced from proto/game_engine.proto
  by `protoc --elixir_out=plugins=grpc`. Talks plaintext HTTP/2 (h2c, no TLS),
  matching the spike server - see GIF-38.

  Field names on the generated structs are the exact PascalCase names from the
  C# [ProtoMember] properties (e.g. `:Owner`, `:AreaId` -> here `:Number`), not
  snake_case - protoc-gen-elixir does not rename them. `struct.Field` isn't
  valid Elixir (a capitalized name after `.` parses as an alias), so field
  access below goes through `Map.fetch!/2`.
  """

  alias GlobalCombat.GrpcHost.{NewGameRequest, ResolveTurnRequest, Order, Game, GameEngine}

  def demo do
    host = System.get_env("GRPC_HOST", "localhost")
    port = System.get_env("GRPC_PORT", "5251") |> String.to_integer()

    IO.puts("Connecting to #{host}:#{port} (plaintext h2c)...")
    {:ok, channel} = GRPC.Stub.connect("#{host}:#{port}")

    {:ok, new_game_reply} =
      GameEngine.Stub.new_game(channel, %NewGameRequest{
        MapName: :Original,
        PlayerNames: ["Alice", "Bob"]
      })

    game = f(new_game_reply, :Game)

    IO.puts(
      "NewGame: id=#{f(game, :Id)} started=#{f(game, :Started)} areas=#{length(f(game, :Areas))} players=#{length(f(game, :Players))}"
    )

    for p <- f(game, :Players) do
      IO.puts(
        "  Player ##{f(p, :Number)} #{f(p, :Name)}: #{f(p, :Areas)} areas, #{f(p, :Armies)} armies (#{f(p, :UnassignedArmies)} unassigned)"
      )
    end

    # AreaInfo (map geometry/links) is never on the wire - only Area.Number is a
    # [ProtoMember]. Area 1 (Alaska) links to Area 2 in the "original" map
    # (see GlobalCombat.Core/MapInfo.cs); both sides know that layout because
    # it's a fixed constant, not because it crossed the wire.
    [source_area | _] =
      Enum.filter(f(game, :Areas), fn a ->
        owner = f(a, :Owner)
        owner && f(owner, :Number) == 1
      end)

    target_area = Enum.find(f(game, :Areas), fn a -> f(a, :Number) == 2 end)

    IO.puts(
      "Order: Area ##{f(source_area, :Number)} (owner ##{f(f(source_area, :Owner), :Number)}) attacks Area ##{f(target_area, :Number)} (owner ##{f(f(target_area, :Owner), :Number)})"
    )

    orders = [
      %Order{
        SourceAreaNumber: f(source_area, :Number),
        TargetAreaNumber: f(target_area, :Number),
        Amount: max(1, f(source_area, :Armies) + f(source_area, :AssignedArmies) - 1),
        Command: :Attack
      }
    ]

    resolve_request = %ResolveTurnRequest{Game: game, Orders: orders}

    request_bytes = ResolveTurnRequest.encode(resolve_request)
    IO.puts("Request wire size (pre-turn Game + orders): #{byte_size(request_bytes)} bytes")

    {:ok, resolved_reply} = GameEngine.Stub.resolve_turn(channel, resolve_request)

    response_bytes = GlobalCombat.GrpcHost.ResolveTurnResponse.encode(resolved_reply)
    IO.puts("Response wire size (resolved Game + summary): #{byte_size(response_bytes)} bytes")

    resolved = f(resolved_reply, :Game)
    IO.puts("\nResolveTurn: Turn=#{f(resolved, :Turn)}")
    IO.puts("TurnSummary: #{f(resolved_reply, :TurnSummary)}")

    print_correctness_check(resolved)

    GRPC.Stub.disconnect(channel)
    :ok
  end

  # See the GIF-38 write-up: Game.RunTurn() totals each player's armies by
  # scanning Areas for `area.Owner == player` - C# reference equality, since
  # Player has no Equals override. This recomputes the same total independently
  # by Number (a value, always correct) and compares it against what the
  # server's RunTurn actually produced, to make a silent correctness bug (if
  # AsReference identity did not survive the wire) visible instead of assumed.
  defp print_correctness_check(%Game{} = game) do
    IO.puts(
      "\nCorrectness check (RunTurn's Armies total vs. independently recomputed by Area.Owner.Number):"
    )

    for p <- f(game, :Players) do
      expected =
        f(game, :Areas)
        |> Enum.filter(fn a ->
          owner = f(a, :Owner)
          owner && f(owner, :Number) == f(p, :Number)
        end)
        |> Enum.reduce(0, fn a, acc -> acc + f(a, :Armies) end)
        |> Kernel.+(f(p, :UnassignedArmies))

      actual = f(p, :Armies)
      verdict = if actual == expected, do: "MATCH", else: "*** MISMATCH ***"

      IO.puts(
        "  Player ##{f(p, :Number)} #{f(p, :Name)}: RunTurn Armies=#{actual}, recomputed=#{expected} #{verdict}"
      )
    end
  end

  defp f(struct, key), do: Map.fetch!(struct, key)
end
