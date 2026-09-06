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
end
