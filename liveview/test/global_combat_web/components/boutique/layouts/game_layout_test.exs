defmodule GlobalCombatWeb.Components.Boutique.Layouts.GameLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

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

    assert html =~ "[grid-template-areas:&#39;status&#39;_&#39;board&#39;_&#39;players&#39;]"
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

    assert html =~ "[grid-template-areas:&#39;status&#39;_&#39;players&#39;_&#39;board&#39;]"
    assert html =~ "lg:[grid-template-areas:&#39;status_status&#39;_&#39;board_players&#39;]"
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

    refute html =~ "game-drawer"
  end

  describe "stage mode (mobile battle mode WP3)" do
    test "stage renders the status/board/dock grid below lg:, h-[100dvh], and no page scroll" do
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

      assert html =~ "[grid-template-areas:&#39;status&#39;_&#39;board&#39;_&#39;dock&#39;]"
      assert html =~ "h-[100dvh]"
      assert html =~ "overflow-hidden"
      assert html =~ "pt-[env(safe-area-inset-top)]"
      # lg: gets a second rail row for :dock above :players — the side-by-side
      # shape (board next to the rail) is otherwise untouched.
      assert html =~
               "lg:[grid-template-areas:&#39;status_status&#39;_&#39;board_dock&#39;_&#39;board_players&#39;]"
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
      assert length(:binary.matches(html, "aria-label=\"Actions\"")) == 1
      assert length(:binary.matches(html, ~s(id="end-turn"))) == 1

      assert html =~
               ~r/<section[^>]*aria-label="Actions"[^>]*class="[^"]*\[grid-area:dock\][^"]*max-h-\[45dvh\][^"]*overflow-y-auto[^"]*lg:max-h-none[^"]*lg:overflow-visible[^"]*lg:border-l[^"]*"[^>]*>/

      assert html =~ ~r/pb-\[max\(var\(--space-3\),env\(safe-area-inset-bottom\)\)\]/
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

      refute html =~ "End Turn"
      refute html =~ ~s(aria-label="Actions")
      refute html =~ "h-[100dvh]"
    end
  end
end
