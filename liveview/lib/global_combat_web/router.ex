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
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GlobalCombatWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Bootstrap smoke page for the vendored design-boutique layer. Remove when
    # the real board LiveView lands (GIF-30).
    live "/design", DesignSmokeLive
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
