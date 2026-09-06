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
  import GlobalCombatWeb.CoreComponents, only: [icon: 1]

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
      </:topbar>
      <:sidebar>
        <!-- Below `lg:` this nav used to render at full height (7 links, ~273px)
        between the topbar and the page content, pushing the game board down a
        full screen's worth on phone/tablet. A `<details>` disclosure
        collapses it to a single "Menu" row by default on narrow screens;
        `group-open:flex` reveals it once tapped. At `lg:` the summary toggle
        hides and `lg:flex` forces the nav visible regardless of the `open`
        attribute, so nothing changes for the desktop persistent sidebar. -->
        <details class="group">
          <summary class="flex cursor-pointer list-none items-center justify-between gap-[var(--space-2)] text-sm font-semibold lg:hidden [&::-webkit-details-marker]:hidden">
            Menu <.icon name="hero-chevron-down" class="size-4 group-open:rotate-180" />
          </summary>
          <nav class="mt-[var(--space-2)] hidden flex-col gap-[var(--space-2)] text-sm group-open:flex lg:mt-0 lg:flex">
            <a href="/" class="hover:underline">Home</a>
            <a href={~p"/Game-Manual"} class="hover:underline">Game Manual</a>
            <hr class="border-border my-[var(--space-2)]" />
            <%= if @current_account do %>
              <a href={~p"/Create-Game"} class="hover:underline">New Game</a>
              <a href={~p"/Messages"} class="hover:underline">Messages</a>
              <a href={~p"/account/settings"} class="hover:underline">Settings</a>
              <hr class="border-border my-[var(--space-2)]" />
              <a href={~p"/account/contact"} class="hover:underline">Contact Us</a>
              <hr class="border-border my-[var(--space-2)]" />
              <form method="post" action={~p"/account/log-off"}>
                <input type="hidden" name="_method" value="delete" />
                <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
                <button type="submit" class="hover:underline text-left cursor-pointer">Log Off</button>
              </form>
            <% else %>
              <a href={~p"/account/log-on"} class="hover:underline">Log On</a>
              <a href={~p"/account/register"} class="hover:underline">New Account</a>
            <% end %>
          </nav>
        </details>
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
end
