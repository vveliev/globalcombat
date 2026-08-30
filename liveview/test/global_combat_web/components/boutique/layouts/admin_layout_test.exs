defmodule GlobalCombatWeb.Components.Boutique.Layouts.AdminLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.Layouts.AdminLayout

  test "renders a skip link before the sidebar nav, targeting the main landmark" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AdminLayout.admin_layout>
        <:sidebar>
          <a href="/">Home</a>
        </:sidebar>
        <:content>Page content</:content>
      </AdminLayout.admin_layout>
      """)

    skip_link_index = :binary.match(html, ~s(href="#main-content")) |> elem(0)
    nav_index = :binary.match(html, "<nav") |> elem(0)
    main_index = :binary.match(html, ~s(id="main-content")) |> elem(0)

    assert html =~ "Skip to main content"
    assert skip_link_index < nav_index
    assert main_index > skip_link_index
    assert html =~ ~s(id="main-content")
    assert html =~ ~s(tabindex="-1")
  end

  test "the skip link is visually hidden until focused" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AdminLayout.admin_layout>
        <:content>Page content</:content>
      </AdminLayout.admin_layout>
      """)

    assert html =~ "sr-only"
    assert html =~ "focus:not-sr-only"
  end
end
