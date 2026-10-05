defmodule GlobalCombatWeb.Components.Boutique.Layouts.GameLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import GlobalCombatWeb.HTMLAssertions

  alias GlobalCombatWeb.Components.Boutique.Layouts.GameLayout

  test "defaults to a status/board/players stacked order below lg:" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameLayout.game_layout>
        <:board>Board</:board>
        <:players>Players</:players>
      </GameLayout.game_layout>
      """)

    assert "[grid-template-areas:'status'_'board'_'players']" in grid_classes(html)
  end

  test "players_first flips to status/players/board below lg: without touching the lg: side-by-side order" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameLayout.game_layout players_first>
        <:board>Board</:board>
        <:players>Players</:players>
      </GameLayout.game_layout>
      """)

    grid = grid_classes(html)

    assert "[grid-template-areas:'status'_'players'_'board']" in grid
    assert "lg:[grid-template-areas:'status_status'_'board_players']" in grid
  end

  test "the :players slot renders once, inside the game-drawer dialog with a Close button" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameLayout.game_layout>
        <:board>Board</:board>
        <:players>Players content</:players>
      </GameLayout.game_layout>
      """)

    document = LazyHTML.from_fragment(html)
    drawer = LazyHTML.query(document, "dialog#game-drawer")

    assert Enum.count(drawer) == 1
    assert LazyHTML.attribute(drawer, "aria-label") == ["Players and chat"]
    assert LazyHTML.text(drawer) =~ "Players content"
    # "Players content" renders exactly once across the whole tree — a
    # hidden duplicate (one copy per breakpoint) would break the DOM ids
    # chat and roster carry, so this can't just check it's inside the dialog.
    assert LazyHTML.text(document) |> String.split("Players content") |> length() == 2

    # Colocated hook names starting with "." expand to the fully-qualified
    # module name at compile time, so this asserts the hook is wired at all
    # rather than pinning the exact expanded string.
    assert [hook] = LazyHTML.attribute(drawer, "phx-hook")
    assert hook =~ ~r/Drawer$/

    close = LazyHTML.query(document, "dialog#game-drawer button[data-drawer-close]")
    assert Enum.count(close) == 1
    assert LazyHTML.attribute(close, "type") == ["button"]
  end

  test "omitting the :players slot renders no drawer at all" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <GameLayout.game_layout>
        <:board>Board</:board>
      </GameLayout.game_layout>
      """)

    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query("dialog, #game-drawer, .game-drawer") |> Enum.empty?()
  end

  describe "stage mode (mobile battle mode WP3)" do
    test "stage renders the status/board/dock grid below lg:, --size-stage tall, and no page scroll" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout stage>
          <:status>Status</:status>
          <:board>Board</:board>
          <:dock>Dock</:dock>
          <:players>Players</:players>
        </GameLayout.game_layout>
        """)

      grid = grid_classes(html)

      assert "[grid-template-areas:'status'_'board'_'dock']" in grid
      assert "h-[var(--size-stage)]" in grid
      assert "overflow-hidden" in grid
      assert "pt-[env(safe-area-inset-top)]" in grid
      # lg: gets a second rail row for :dock above :players — the side-by-side
      # shape (board next to the rail) is otherwise untouched.
      assert "lg:[grid-template-areas:'status_status'_'board_dock'_'board_players']" in grid
    end

    test "stage's dock renders once — a bottom sheet below lg:, repositioned to the top of the rail at lg: via grid-area, never duplicated" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout stage>
          <:board>Board</:board>
          <:dock><button id="end-turn">End Turn</button></:dock>
          <:players>Roster</:players>
        </GameLayout.game_layout>
        """)

      # Exactly one dock section, exactly one id="end-turn" — never duplicated
      # (a duplicate would also mean order-panel/order-form ids collide once
      # GameLive wires a real order form into :dock).
      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query(~s([aria-label="Actions"])) |> Enum.count() == 1
      assert document |> LazyHTML.query(~s([id="end-turn"])) |> Enum.count() == 1

      dock = document |> LazyHTML.query(~s(section[aria-label="Actions"])) |> classes()

      for class <- ~w|
            [grid-area:dock] max-h-[var(--size-dock-max)] overflow-y-auto
            lg:max-h-none lg:overflow-visible lg:border-l
            pb-[max(var(--space-3),env(safe-area-inset-bottom))]
          | do
        assert class in dock
      end
    end

    test "stage mode doesn't disturb the :players drawer — it's still the one game-drawer dialog" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout stage>
          <:board>Board</:board>
          <:dock>Dock</:dock>
          <:players>Roster</:players>
        </GameLayout.game_layout>
        """)

      document = LazyHTML.from_fragment(html)
      drawer = LazyHTML.query(document, "dialog#game-drawer")

      assert Enum.count(drawer) == 1
      assert LazyHTML.text(drawer) =~ "Roster"
    end

    test "stage turns on the HUD (data-hud) even with no dock, as for a viewer without a seat" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout stage>
          <:board>Board</:board>
          <:players>Roster</:players>
        </GameLayout.game_layout>
        """)

      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("div[data-hud]") |> Enum.count() == 1
      assert document |> LazyHTML.query(~s([aria-label="Actions"])) |> Enum.empty?()

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout>
          <:board>Board</:board>
        </GameLayout.game_layout>
        """)

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-hud]") |> Enum.empty?()
    end

    test "without stage, the dock slot is ignored entirely — output matches today's shape" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <GameLayout.game_layout>
          <:board>Board</:board>
          <:dock>End Turn</:dock>
          <:players>Players</:players>
        </GameLayout.game_layout>
        """)

      document = LazyHTML.from_fragment(html)

      refute LazyHTML.text(document) =~ "End Turn"
      assert document |> LazyHTML.query(~s([aria-label="Actions"])) |> Enum.empty?()
      assert document |> LazyHTML.query(~s|[class~="h-[var(--size-stage)]"]|) |> Enum.empty?()
    end
  end

  # The shell's outer grid container — the one top-level element of the fragment.
  defp grid_classes(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.filter("div") |> classes()
end
