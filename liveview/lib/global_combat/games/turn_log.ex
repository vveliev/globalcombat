defmodule GlobalCombat.Games.TurnLog do
  @moduledoc """
  The persisted shape of one resolved turn's event log: `GlobalCombat.Engine.Game.resolve_turn/1`'s
  ordered `events`, the pre-resolution area-ownership snapshot `GlobalCombat.Games.PlayerView`'s fog
  rule needs (`before_owners` -- see its moduledoc's "Turn-resolution event visibility" section), and
  the `turn` number they both belong to.

  Stamping `turn` isn't just informational: `GlobalCombat.Games.persist_turn/3` writes
  `games.serialized` and `games.last_turn_events` in one statement so the pair can't land as two
  independently-crashable writes, but `PlayerView.build/3` still checks this `turn` against the
  engine's own current `turn` before trusting the log at all -- a second, structural line of
  defense against a log that's stale relative to the state it's paired with (for instance a game
  rehydrated from a `serialized` snapshot one turn ahead of its `last_turn_events` column).

  Built once per resolved turn -- by `GlobalCombat.Games.Server` right after a live turn resolves,
  and by `GlobalCombat.Games.LiveResolver`'s offline path -- previously duplicated inline in both.
  """

  alias GlobalCombat.Engine.Game, as: Engine

  defstruct turn: nil, events: [], before_owners: %{}

  @doc """
  Builds the log for a turn just resolved from `old_engine` (pre-resolution, read only for its
  `before_owners` ownership snapshot) to `new_engine` (post-resolution -- its `turn` is already
  incremented by `Engine.resolve_turn/1`, and is the turn number `events` describes).
  """
  def snapshot(%Engine{} = old_engine, %Engine{} = new_engine, events) do
    %__MODULE__{
      turn: new_engine.turn,
      events: events,
      before_owners:
        Map.new(old_engine.areas, fn {number, area} -> {number, area.owner_number} end)
    }
  end

  @doc "Encodes a log for the `games.last_turn_events` column."
  def encode(%__MODULE__{} = log), do: :erlang.term_to_binary(log)

  @doc """
  Decodes a `GlobalCombat.Games.persist_turn/3`-written blob back into a `%TurnLog{}`. `nil`
  covers both a game rehydrated before this column existed and one no turn has resolved for
  since -- decodes to the empty log (`turn: nil`, which `PlayerView.build/3` treats the same as
  any other turn mismatch: nothing to show).
  """
  def decode(nil), do: %__MODULE__{}
  def decode(binary) when is_binary(binary), do: :erlang.binary_to_term(binary)
end
