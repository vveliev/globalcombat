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
  """

  use Phoenix.Component
  use GlobalCombatWeb, :verified_routes

  import Phoenix.Controller, only: [get_csrf_token: 0]

  attr :current_account, :any, default: nil
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
        <nav class="flex flex-col gap-[var(--space-2)] text-sm">
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
      </:sidebar>
      <:content>
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
