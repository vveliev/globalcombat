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

  `current_path` marks the matching sidebar link `aria-current="page"`. It is rendered
  server-side rather than patched in by a script because this chrome sits inside LiveViews
  as well as controller pages: a client-side attribute would not survive LiveView's first
  patch after the socket joins, and would never re-run on live navigation. Controller
  pages get the assign from `GlobalCombatWeb.Plugs.CurrentPath`; LiveViews get it from the
  `handle_params` hook `GlobalCombatWeb.UserAuth.on_mount/4` attaches.
  """

  use Phoenix.Component
  use GlobalCombatWeb, :verified_routes

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import GlobalCombatWeb.CoreComponents, only: [icon: 1]

  alias GlobalCombatWeb.Layouts

  attr :current_account, :any, default: nil
  attr :page_title, :string, default: nil
  attr :current_path, :string, default: nil, doc: "request path, for the active sidebar link"
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
        <%!-- Below `lg:` this nav used to render at full height (7 links, ~273px)
        between the topbar and the page content, pushing the game board down a
        full screen's worth on phone/tablet. A single `<nav>` toggled with
        `hidden lg:flex`/`<details>` can't serve both breakpoints: a closed
        `<details>` hides its content at the UA level (Chromium >=131 via
        `::details-content { content-visibility: hidden }`, older engines via
        an unrendered slot) regardless of an author `display` override, so
        `lg:flex` on the nested `<nav>` never actually shows it again past
        `lg:` — reproduced with `checkVisibility() === false` despite a
        computed `display:flex` at 1280px. Two separate markup branches next
        to each other avoids fighting that: a plain nav shown `hidden lg:flex`
        for `lg:` and above, and a `<details>` disclosure shown only
        `lg:hidden` below it, each with its own copy of the links. --%>
        <nav class="hidden lg:flex lg:flex-col lg:gap-[var(--space-2)] text-sm">
          {sidebar_links(assigns)}
        </nav>
        <details class="group lg:hidden">
          <summary class="flex cursor-pointer list-none items-center justify-between gap-[var(--space-2)] text-sm font-semibold [&::-webkit-details-marker]:hidden">
            Menu <.icon name="hero-chevron-down" class="size-4 group-open:rotate-180" />
          </summary>
          <nav class="mt-[var(--space-2)] hidden flex-col gap-[var(--space-2)] text-sm group-open:flex">
            {sidebar_links(assigns)}
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

  attr :current_account, :any, required: true
  attr :current_path, :string, required: true

  defp sidebar_links(assigns) do
    ~H"""
    <.nav_link href="/" current_path={@current_path}>Home</.nav_link>
    <.nav_link href={~p"/Game-Manual"} current_path={@current_path}>Game Manual</.nav_link>
    <hr class="border-border my-[var(--space-2)]" />
    <%= if @current_account do %>
      <.nav_link href={~p"/Create-Game"} current_path={@current_path}>New Game</.nav_link>
      <.nav_link href={~p"/Messages"} current_path={@current_path}>Messages</.nav_link>
      <.nav_link href={~p"/account/settings"} current_path={@current_path}>Settings</.nav_link>
      <hr class="border-border my-[var(--space-2)]" />
      <.nav_link href={~p"/account/contact"} current_path={@current_path}>Contact Us</.nav_link>
      <hr class="border-border my-[var(--space-2)]" />
      <form method="post" action={~p"/account/log-off"}>
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <button type="submit" class={nav_link_class()}>Log Off</button>
      </form>
    <% else %>
      <.nav_link href={~p"/account/log-on"} current_path={@current_path}>Log On</.nav_link>
      <.nav_link href={~p"/account/register"} current_path={@current_path}>New Account</.nav_link>
    <% end %>
    """
  end

  attr :href, :string, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <a href={@href} aria-current={@current_path == @href && "page"} class={nav_link_class()}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  # Shared by every sidebar `<a>` and the "Log Off" `<button>` (semantically a
  # form submit, styled as a nav item) so the two element kinds can never
  # drift apart, and so `aria-current="page"` has a visual hook to land on.
  defp nav_link_class do
    [
      "rounded-[var(--radius-sm)] px-[var(--space-2)] py-[var(--space-1)] text-left cursor-pointer",
      "hover:bg-surface-muted hover:underline",
      "aria-[current=page]:bg-surface-muted aria-[current=page]:font-semibold aria-[current=page]:text-text"
    ]
  end
end
