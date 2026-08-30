# Minimal repro for the GIF-72 sweep crash: scenario 10 of the main matrix
# (map=Original, players=3, fogged=false, non_random=false, reverse=true,
# min_armies=3, games=3, turns=120, seed_base=46) failed partway through with
#   ** (MatchError) no match of right hand side value:
#     {:error, %GRPC.RPCError{status: 2, message: "Exception was thrown by handler."}}
# from harness.ex:127 (the ResolveQueuedTurn call). Runs each of the 3 games
# turn-by-turn against a freshly started oracle and reports exactly which
# game_seed/turn_index the oracle's ResolveQueuedTurn call fails on.

Application.ensure_all_started(:gun)
Application.ensure_all_started(:grpc)

alias GlobalCombat.GrpcHost.{GameEngine, NewGameRequest, ResolveQueuedTurnRequest, ThinkRequest}

host = System.get_env("GRPC_HOST", "localhost")
port = System.get_env("GRPC_PORT", "5251") |> String.to_integer()

{:ok, channel} = GRPC.Stub.connect("#{host}:#{port}")

scenario_base_seed = 46

for game_index <- 1..3 do
  game_seed = scenario_base_seed + game_index
  IO.puts("=== game_seed=#{game_seed} ===")

  {:ok, new_game_reply} =
    GameEngine.Stub.new_game(channel, %NewGameRequest{
      MapName: :Original,
      PlayerNames: ["Alice", "Bob", "Carol"],
      Seed: game_seed,
      IsNonRandom: false,
      IsFogged: false,
      ReverseAttackOrder: true,
      MinimumArmies: 3
    })

  game_id = Map.fetch!(Map.fetch!(new_game_reply, :Game), :Id)

  Enum.reduce_while(1..120, :ok, fn turn_index, :ok ->
    think_seed = game_seed * 1_000_000 + turn_index * 2
    resolve_seed = think_seed + 1

    case GameEngine.Stub.think(channel, %ThinkRequest{GameId: game_id, Seed: think_seed}) do
      {:ok, _think_reply} ->
        case GameEngine.Stub.resolve_queued_turn(channel, %ResolveQueuedTurnRequest{
               GameId: game_id,
               Seed: resolve_seed
             }) do
          {:ok, resolve_reply} ->
            if Map.fetch!(Map.fetch!(resolve_reply, :Game), :Ended) do
              IO.puts("  turn #{turn_index}: game ended cleanly")
              {:halt, :ended}
            else
              {:cont, :ok}
            end

          {:error, error} ->
            IO.puts(
              "  turn #{turn_index}: RESOLVE FAILED think_seed=#{think_seed} resolve_seed=#{resolve_seed}: #{inspect(error)}"
            )

            {:halt, :resolve_failed}
        end

      {:error, error} ->
        IO.puts("  turn #{turn_index}: THINK FAILED think_seed=#{think_seed}: #{inspect(error)}")
        {:halt, :think_failed}
    end
  end)
  |> then(&IO.puts("  result: #{inspect(&1)}"))
end

GRPC.Stub.disconnect(channel)
