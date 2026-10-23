defmodule GlobalCombatWeb.GameLive.Chat do
  @moduledoc """
  The game's chat box in the players drawer/rail: a send form for logged-in viewers (the
  `send_chat` event `GameLive` handles) above the newest-first message log, which is a polite
  live region so incoming messages are announced without interrupting.

  Submitting also dispatches `gc:reset-form` on the form (handled in `app.js`) so the
  message box empties at once: LiveView never patches the value of the focused input, so
  the server's blank `chat_form` alone leaves the sent text in place to be sent twice.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Input

  attr :messages, :list, required: true
  attr :chat_form, Phoenix.HTML.Form, required: true
  attr :logged_in, :boolean, required: true

  def chat(assigns) do
    ~H"""
    <div class="mt-[var(--space-4)] flex flex-col gap-[var(--space-2)]">
      <.form
        :if={@logged_in}
        for={@chat_form}
        id="chat-form"
        phx-submit={JS.push("send_chat") |> JS.dispatch("gc:reset-form", to: "#chat-form")}
        class="flex flex-col gap-[var(--space-2)]"
      >
        <Input.input
          id="chat-message"
          name="text"
          field={@chat_form[:text]}
          label="Message"
          placeholder="Send a message"
          class="min-w-0"
        />
        <Button.button type="submit" intent="neutral" class="self-end">Send</Button.button>
      </.form>
      <ul
        aria-live="polite"
        id="chat-messages"
        class="flex flex-col-reverse gap-[var(--space-1)] text-sm"
      >
        <li :if={@messages == []} class="text-text-muted">No messages yet.</li>
        <li :for={m <- @messages} data-message>
          <span class="font-semibold">{m.source_name}:</span> {m.text}
        </li>
      </ul>
    </div>
    """
  end
end
