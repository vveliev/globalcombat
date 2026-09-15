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

  describe "immersive (SiteChrome's stage-mode passthrough, mobile battle mode WP3)" do
    test "hides the topbar and sidebar below lg: and drops content padding, unchanged at lg:" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <AdminLayout.admin_layout immersive>
          <:sidebar>Sidebar</:sidebar>
          <:topbar>Topbar</:topbar>
          <:content>Content</:content>
        </AdminLayout.admin_layout>
        """)

      assert html =~ "[grid-template-areas:&#39;content&#39;]"
      assert html =~ ~r/<nav[^>]*class="[^"]*\bhidden\b[^"]*\blg:block\b[^"]*"/
      assert html =~ ~r/<header[^>]*class="[^"]*\bhidden\b[^"]*\blg:flex\b[^"]*"/
      assert html =~ ~r/<main[^>]*class="[^"]*\bp-0\b[^"]*lg:p-\[var\(--space-6\)\][^"]*"/
      # The lg: side-by-side order is untouched by immersive.
      assert html =~ "lg:[grid-template-areas:&#39;sidebar_topbar&#39;_&#39;sidebar_content&#39;]"
    end

    test "without immersive, output matches today's shape" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <AdminLayout.admin_layout>
          <:sidebar>Sidebar</:sidebar>
          <:topbar>Topbar</:topbar>
          <:content>Content</:content>
        </AdminLayout.admin_layout>
        """)

      refute html =~ "hidden lg:block"
      refute html =~ "hidden lg:flex"
      assert html =~ "[grid-template-areas:&#39;topbar&#39;_&#39;sidebar&#39;_&#39;content&#39;]"
    end
  end
end
