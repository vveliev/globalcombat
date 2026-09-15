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

    assert [_one] = Regex.scan(~r/Players content/, html)
    assert html =~ ~r/<dialog[^>]*id="game-drawer"[^>]*>.*Players content.*<\/dialog>/s
    assert html =~ ~r/<dialog[^>]*aria-label="Players and chat"/
    # Colocated hook names starting with "." expand to the fully-qualified
    # module name at compile time, so this asserts the hook is wired at all
    # rather than pinning the exact expanded string.
    assert html =~ ~r/<dialog[^>]*phx-hook="[^"]*Drawer"/
    assert html =~ ~s(<button type="button" data-drawer-close)
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
end
