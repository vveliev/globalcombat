defmodule Mix.Tasks.GameEngine.ResolveTurn do
  @moduledoc """
  GIF-38 spike: creates a game and resolves one turn through the GlobalCombat
  gRPC host, using only the generated protobuf/gRPC client - no Ecto, no
  Endpoint, no MySQL. That's deliberate: it demonstrates that under option 4
  Phoenix does not need to touch the game-state DB column itself.

      GRPC_HOST=localhost GRPC_PORT=5251 mix game_engine.resolve_turn
  """
  use Mix.Task

  @shortdoc "Resolve one turn through the GlobalCombat gRPC host"

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:gun)
    {:ok, _} = Application.ensure_all_started(:grpc)
    GlobalCombat.GameEngine.Client.demo()
  end
end
