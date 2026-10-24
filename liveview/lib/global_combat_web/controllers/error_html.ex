defmodule GlobalCombatWeb.ErrorHTML do
  @moduledoc """
  HTML error pages. `404.html.heex` and `500.html.heex` render inside the site chrome
  through the root layout (`render_errors: [root_layout: ...]` in `config/config.exs`);
  any other status falls through to `render/2` and gets the same page with Plug's status
  phrase, so no error lands on a bare "Not Found" string again.

  Nothing here may depend on pipeline assigns: a `NoRouteError` is raised before the
  `:browser` pipeline runs, so there is no `current_account`, session or flash — the
  chrome renders its logged-out nav in that case. Errors raised inside a controller do
  carry the pipeline's assigns, and the chrome picks them up.
  """
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]
  alias GlobalCombatWeb.Components.Boutique.{Button, Kicker}

  embed_templates "error_html/*"

  @doc """
  Render the 404 page from a controller or plug that found nothing, and halt. Replaces
  the `send_resp(404, "Not Found")` / `text("Not Found")` answers the legacy-id routes
  gave, which bypassed this module entirely.
  """
  def not_found(conn) do
    conn
    |> Plug.Conn.put_status(:not_found)
    |> Phoenix.Controller.put_view(html: __MODULE__)
    |> Phoenix.Controller.render(:"404")
    |> Plug.Conn.halt()
  end

  def render(template, assigns) do
    [status | _] = String.split(template, ".")

    assigns
    |> Map.new()
    |> Map.merge(%{
      status: String.to_integer(status),
      title: Phoenix.Controller.status_message_from_template(template),
      message: "That request couldn't be completed. Head back to Home and try again."
    })
    |> error_page()
  end

  attr :status, :integer, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  attr :current_account, :any, default: nil
  attr :current_path, :string, default: nil

  def error_page(assigns) do
    ~H"""
    <.site_chrome current_account={@current_account} current_path={@current_path}>
      <div class="mx-auto w-full max-w-md py-[var(--space-8)] flex flex-col gap-[var(--space-6)]">
        <header class="flex flex-col gap-[var(--space-2)]">
          <Kicker.kicker>Error {@status}</Kicker.kicker>
          <h1 class="heading-3">{@title}</h1>
          <p class="text-sm text-text-muted">{@message}</p>
        </header>
        <div class="flex flex-wrap gap-[var(--space-3)]">
          <Button.button href="/" class="min-h-[var(--size-touch-target)] touch-manipulation">
            Back to Home
          </Button.button>
          <Button.button
            href={~p"/Game-Manual"}
            intent="neutral"
            class="min-h-[var(--size-touch-target)] touch-manipulation"
          >
            Game Manual
          </Button.button>
        </div>
      </div>
    </.site_chrome>
    """
  end
end
