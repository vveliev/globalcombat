defmodule GlobalCombatWeb.Components.Boutique.Layouts.AdminLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import GlobalCombatWeb.HTMLAssertions

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

    doc = LazyHTML.from_fragment(html)
    skip_link = LazyHTML.query(doc, ~s(a[href="#main-content"]))

    assert LazyHTML.text(skip_link) =~ "Skip to main content"
    # `query/2` returns matches in document order: skip link, then nav, then main.
    assert doc |> LazyHTML.query(~s(a[href="#main-content"], nav, main)) |> LazyHTML.tag() ==
             ["a", "nav", "main"]

    assert doc |> LazyHTML.query(~s(main#main-content[tabindex="-1"])) |> Enum.count() == 1
  end

  test "the skip link is visually hidden until focused" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AdminLayout.admin_layout>
        <:content>Page content</:content>
      </AdminLayout.admin_layout>
      """)

    skip_link = html |> LazyHTML.from_fragment() |> LazyHTML.query(~s(a[href="#main-content"]))

    assert "sr-only" in classes(skip_link)
    assert "focus:not-sr-only" in classes(skip_link)
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

      doc = LazyHTML.from_fragment(html)
      grid = doc |> LazyHTML.filter("div") |> classes()
      nav = doc |> LazyHTML.query("nav") |> classes()
      header = doc |> LazyHTML.query("header") |> classes()
      main = doc |> LazyHTML.query("main") |> classes()

      assert "[grid-template-areas:'content']" in grid
      assert "hidden" in nav and "lg:block" in nav
      assert "hidden" in header and "lg:flex" in header
      assert "p-0" in main and "lg:p-[var(--space-6)]" in main
      # The lg: side-by-side order is untouched by immersive.
      assert "lg:[grid-template-areas:'sidebar_topbar'_'sidebar_content']" in grid
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

      doc = LazyHTML.from_fragment(html)
      grid = doc |> LazyHTML.filter("div") |> classes()
      nav = doc |> LazyHTML.query("nav") |> classes()
      header = doc |> LazyHTML.query("header") |> classes()

      refute "hidden" in nav or "lg:block" in nav
      refute "hidden" in header or "lg:flex" in header
      assert "[grid-template-areas:'topbar'_'sidebar'_'content']" in grid
    end
  end
end
