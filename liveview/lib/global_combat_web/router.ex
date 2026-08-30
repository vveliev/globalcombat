defmodule GlobalCombatWeb.Router do
  use GlobalCombatWeb, :router

  import GlobalCombatWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GlobalCombatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_account
    plug :fetch_open_chat_windows
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GlobalCombatWeb do
    pipe_through :browser

    get "/", HomeController, :index

    # Bootstrap smoke page for the vendored design-boutique layer. Remove when
    # the real board LiveView lands (GIF-30).
    live "/design", DesignSmokeLive

    # --- Legacy globalcombat.com URL scheme (live since 2001-01-22) — GIF-31 ---
    # Mirrors the explicit MapControllerRoute calls in Web/Program.cs so 25
    # years of inbound links, bookmarks and search results keep resolving.
    # Do not "clean up" these paths into e.g. /games/:id — if new canonical
    # paths are ever added, these must 301 to them, not disappear.
    #
    # Literal/shortcut routes are declared before the "Game-:id" pattern
    # below so e.g. /Game-Manual doesn't get swallowed as id: "Manual".
    get "/Create-Tournament", TourneyController, :new
    post "/Create-Tournament", TourneyController, :create
    get "/Game-Manual", HomeController, :game_manual
    post "/Send-Message", HomeController, :send_message

    # The `{action}` shortcut set, constrained in Program.cs to exactly:
    # Messages|Stats|IpAddresses|GameManual|OptOut|PlayerInfo|Chat|
    # LoadChatMessages|CloseChatWindow|SendMessage
    #
    # None of these carried an `[HttpPost]` attribute in the .NET app (only the
    # OptOut *confirmation* did), so ASP.NET's conventional routing accepted
    # either verb — but `Web/wwwroot/Global.js` only ever issues `$.post(...)`
    # for Chat/LoadChatMessages/CloseChatWindow/SendMessage (GIF-33 research).
    # Both verbs are kept here for the shortcut paths (URL-shape fidelity,
    # GIF-31); the `/Home/...` paths the JS actually calls are POST-only below.
    get "/Messages", HomeController, :messages
    get "/Stats", HomeController, :stats
    get "/IpAddresses", HomeController, :ip_addresses
    get "/GameManual", HomeController, :game_manual
    get "/OptOut", HomeController, :opt_out
    post "/OptOut", HomeController, :opt_out
    get "/PlayerInfo", HomeController, :player_info
    get "/Chat", HomeController, :chat
    post "/Chat", HomeController, :chat
    get "/LoadChatMessages", HomeController, :load_chat_messages
    post "/LoadChatMessages", HomeController, :load_chat_messages
    get "/CloseChatWindow", HomeController, :close_chat_window
    post "/CloseChatWindow", HomeController, :close_chat_window
    get "/SendMessage", HomeController, :send_message
    post "/SendMessage", HomeController, :send_message

    # The two concrete instantiations of the ASP.NET default route
    # (`{controller=Home}/{action=Index}/{id?}`) that already have a home in
    # this app. We deliberately do NOT reproduce that route generically —
    # dynamically resolving an arbitrary controller/action pair from user
    # input is both a security smell (arbitrary module/function dispatch)
    # and not how Phoenix routing works. Other legacy default-route
    # destinations (e.g. /Account/LogOn) get explicit routes like the ones
    # above once their controllers are ported.
    get "/Home", HomeController, :index
    get "/Home/Index", HomeController, :index

    # `/Home/{Action}` — the exact paths `Web/wwwroot/Global.js`'s jQuery AJAX
    # calls POST to (`$.post("/Home/Chat", ...)` etc., GIF-33 research), distinct
    # from the bare `/{Action}` shortcut set above.
    post "/Home/Chat", HomeController, :chat
    post "/Home/LoadChatMessages", HomeController, :load_chat_messages
    post "/Home/CloseChatWindow", HomeController, :close_chat_window
    post "/Home/SendMessage", HomeController, :send_message

    get "/Game-:id/:action", GameController, :show
    get "/Player-Info-:id", HomeController, :player_info
    get "/Tournament-:id", TourneyController, :index
    get "/Tournament-:id/Join", TourneyController, :join
    get "/Tournament-:id/Quit", TourneyController, :quit

    # The game board (GIF-30): SignalR + server-rendered HTML replaced by a LiveView
    # driven over GlobalCombat.Games.PubSub. `on_mount` resolves `:current_account`
    # from the session the same way the `:browser` pipeline's `fetch_current_account`
    # does for controllers (see `GlobalCombatWeb.UserAuth.on_mount/4`).
    live_session :game, on_mount: {GlobalCombatWeb.UserAuth, :assign_current_account} do
      live "/Create-Game", GameCreateLive
      live "/Game-:id", GameLive, :show
    end
  end

  # Account surface (GIF-29): register / log on / log off / password reset / settings.
  # Ports Web/Controllers/AccountController.cs and its views.
  scope "/account", GlobalCombatWeb do
    pipe_through [:browser, :redirect_if_account_is_authenticated]

    get "/register", AccountRegistrationController, :new
    post "/register", AccountRegistrationController, :create
    get "/log-on", AccountSessionController, :new
    post "/log-on", AccountSessionController, :create
    get "/reset-password", AccountResetPasswordController, :new
    post "/reset-password", AccountResetPasswordController, :create
  end

  scope "/account", GlobalCombatWeb do
    pipe_through :browser

    delete "/log-off", AccountSessionController, :delete
  end

  scope "/account", GlobalCombatWeb do
    pipe_through [:browser, :require_authenticated_account]

    get "/settings", AccountSettingsController, :edit
    put "/settings/password", AccountSettingsController, :update_password
  end

  # Other scopes may use custom stacks.
  # scope "/api", GlobalCombatWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:global_combat, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GlobalCombatWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
