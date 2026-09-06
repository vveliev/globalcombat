defmodule GlobalCombatWeb.Components.SiteChrome do
  @moduledoc """
  The GlobalCombat site shell for Home/Stats/Messages/PlayerInfo/IpAddresses/OptOut/GameManual
  (GIF-33) — ports `Web/Views/Shared/_Layout.cshtml` + `_DefaultMenu.cshtml` onto the
  design-boutique `admin_layout` shell (`docs/design-boutique/LAYOUTS.md`: "Left sidebar + top
  bar + content", the closest shipped match to the legacy left-menu/center-content shape).

  Dropped rather than ported: the Google Analytics snippet, AdSense slots, the rotating
  `topPic##.jpg` banner image, and the `_gaq`/`google_ad_*` inline scripts — third-party
  tracking/ad cruft with no functional value to the port. The `<audio id="notify">` chime and
  the SignalR bootstrap (`$.popupChat` replay from `OpenChatWindows`) are carried forward,
  wired to `assets/js/chat.js` instead of `Global.js`/jQuery.

  `page_title` renders as a visually-hidden `<h1>` ahead of the content slot. The legacy
  `_Layout.cshtml` never had one either (just a `ViewBag.Title` browser-tab string) — this
  isn't a regression to preserve, since it left every page under this chrome with no
  heading a screen-reader user could jump to for "what page is this" (WCAG 1.3.1, 2.4.6;
  GIF-86). `sr-only` because the design has no visual slot for a page title (`Card`'s own
  `:header` already carries the visible section titles) and this port isn't the place to
  add one.
  """

  use Phoenix.Component
  use GlobalCombatWeb, :verified_routes

  import Phoenix.Controller, only: [get_csrf_token: 0]

  alias GlobalCombatWeb.Layouts

  attr :current_account, :any, default: nil
  attr :page_title, :string, default: nil
  slot :inner_block, required: true

  def site_chrome(assigns) do
    ~H"""
    <GlobalCombatWeb.Components.Boutique.Layouts.AdminLayout.admin_layout>
      <:topbar>
        <a href="/" class="flex items-center gap-[var(--space-2)] font-semibold text-text">
          GLOBAL COMBAT
        </a>
        <div class="ml-auto">
          <Layouts.theme_toggle />
        </div>
      </:topbar>
      <:sidebar>
        <nav id="sidebar-nav" class="flex flex-col gap-[var(--space-2)] text-sm">
          <a href="/" class={nav_link_class()}>Home</a>
          <a href={~p"/Game-Manual"} class={nav_link_class()}>Game Manual</a>
          <hr class="border-border my-[var(--space-2)]" />
          <%= if @current_account do %>
            <a href={~p"/Create-Game"} class={nav_link_class()}>New Game</a>
            <a href={~p"/Messages"} class={nav_link_class()}>Messages</a>
            <a href={~p"/account/settings"} class={nav_link_class()}>Settings</a>
            <hr class="border-border my-[var(--space-2)]" />
            <a href={~p"/account/contact"} class={nav_link_class()}>Contact Us</a>
            <hr class="border-border my-[var(--space-2)]" />
            <form method="post" action={~p"/account/log-off"}>
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <button type="submit" class={nav_link_class()}>Log Off</button>
            </form>
          <% else %>
            <a href={~p"/account/log-on"} class={nav_link_class()}>Log On</a>
            <a href={~p"/account/register"} class={nav_link_class()}>New Account</a>
          <% end %>
        </nav>
        <script>
          (() => {
            const nav = document.getElementById("sidebar-nav");
            if (!nav) return;
            const path = window.location.pathname;
            nav.querySelectorAll("a[href]").forEach((a) => {
              if (a.pathname === path) a.setAttribute("aria-current", "page");
            });
          })();
        </script>
      </:sidebar>
      <:content>
        <h1 :if={@page_title} class="sr-only">{@page_title}</h1>
        {render_slot(@inner_block)}
      </:content>
    </GlobalCombatWeb.Components.Boutique.Layouts.AdminLayout.admin_layout>
    <audio :if={@current_account} id="notify">
      <source src={~p"/Sounds/chime.ogg"} type="audio/ogg" />
      <source src={~p"/Sounds/chime.mp3"} type="audio/mp3" />
    </audio>
    """
  end

  # Shared by every sidebar `<a>` and the "Log Off" `<button>` (semantically a
  # form submit, styled as a nav item) so the two element kinds can never
  # drift apart, and so `aria-current="page"` (set client-side above — the
  # sidebar has no server-side notion of "current path" across both LiveView
  # and plain controller-rendered pages) has a visual hook to land on.
  defp nav_link_class do
    [
      "rounded-[var(--radius-sm)] px-[var(--space-2)] py-[var(--space-1)] text-left cursor-pointer",
      "hover:bg-surface-muted hover:underline",
      "aria-[current=page]:bg-surface-muted aria-[current=page]:font-semibold aria-[current=page]:text-text"
    ]
  end
end
