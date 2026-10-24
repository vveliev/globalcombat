defmodule GlobalCombatWeb.Components.AuthCard do
  @moduledoc """
  Shared frame for the account entry screens (Log On, Register, Lost Password): the site
  chrome (without its sr-only `page_title` heading — the card carries the visible `<h1>`),
  so a visitor keeps the header and nav instead of landing on a bare form, around one
  centered card with a kicker, heading, optional lede, the form, and a footer for the
  "switch to the other screen" link.

  Pass `flash` and an `:info` entry renders above the card: the chrome itself shows no
  flash, so without this the "A new password was sent to your email." message a reset
  redirects to Log On with was never seen.
  """
  use Phoenix.Component

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]
  import GlobalCombatWeb.Components.InlineMessage, only: [inline_message: 1]
  alias GlobalCombatWeb.Components.Boutique.{Card, Kicker}

  attr :title, :string, required: true
  attr :kicker, :string, required: true
  attr :lede, :string, default: nil
  attr :current_account, :any, default: nil
  attr :current_path, :string, default: nil
  attr :flash, :map, default: %{}, doc: "the flash map; its :info entry shows above the card"

  slot :inner_block, required: true
  slot :footer
  slot :aside, doc: "secondary content below the card, e.g. the code of conduct"

  def auth_card(assigns) do
    assigns = assign(assigns, :info_flash, Phoenix.Flash.get(assigns.flash, :info))

    ~H"""
    <.site_chrome
      current_account={@current_account}
      current_path={@current_path}
    >
      <div class="mx-auto w-full max-w-md py-[var(--space-6)] sm:py-[var(--space-8)] flex flex-col gap-[var(--space-5)]">
        <.inline_message :if={@info_flash} id="flash-info" intent="info">
          {@info_flash}
        </.inline_message>
        <Card.card>
          <div class="flex flex-col gap-[var(--space-5)]">
            <header class="flex flex-col gap-[var(--space-2)]">
              <Kicker.kicker>{@kicker}</Kicker.kicker>
              <h1 class="font-heading text-2xl font-[var(--font-heading-weight)] leading-[var(--leading-tight)]">
                {@title}
              </h1>
              <p :if={@lede} class="text-sm text-text-muted">{@lede}</p>
            </header>
            {render_slot(@inner_block)}
          </div>
          <:footer :if={@footer != []}>
            <div class="flex flex-col gap-[var(--space-2)] text-sm">{render_slot(@footer)}</div>
          </:footer>
        </Card.card>
        {render_slot(@aside)}
      </div>
    </.site_chrome>
    """
  end
end
