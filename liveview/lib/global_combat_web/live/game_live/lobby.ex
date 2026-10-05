defmodule GlobalCombatWeb.GameLive.Lobby do
  @moduledoc """
  The pre-start lobby `GameLive` renders into the board slot while the game is still waiting
  for players: the seated roster, Join / Start Game / Quit, and the invite form.

  Every control here only fires an event (`join`, `start`, `quit`, `invite`); `GameLive`
  handles them, so this module stays stateless markup.
  """

  use GlobalCombatWeb, :html

  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Input

  attr :game_id, :integer, required: true
  attr :view, :map, required: true
  attr :invite_login, :string, required: true, doc: "the invite box's current value"

  def lobby(assigns) do
    ~H"""
    <div id="lobby" class="flex flex-col gap-[var(--space-4)]">
      <h2 class="heading-3">
        Game {@game_id}
      </h2>
      <ul id="lobby-players" class="flex flex-col gap-[var(--space-2)]">
        <li :for={p <- @view.players}>Player {p.number}: {p.name}</li>
      </ul>
      <div class="flex gap-[var(--space-3)]">
        <Button.button
          :if={@view.viewer_number == nil}
          id="lobby-join"
          phx-click="join"
          disabled={length(@view.players) >= @view.max_players}
        >
          Join
        </Button.button>
        <Button.button
          :if={@view.viewer_number == 1}
          id="lobby-start"
          intent="primary"
          phx-click="start"
          disabled={length(@view.players) < 2}
        >
          Start Game
        </Button.button>
        <Button.button
          :if={@view.viewer_number != nil}
          id="lobby-quit"
          intent="neutral"
          phx-click="quit"
        >
          Quit
        </Button.button>
      </div>
      <form
        :if={@view.viewer_number != nil}
        id="invite-form"
        phx-submit="invite"
        class="flex gap-[var(--space-2)]"
      >
        <Input.input
          id="invite-login"
          name="login"
          value={@invite_login}
          label="Invite a player"
          placeholder="Username or email"
          class="min-w-0"
        />
        <Button.button id="invite-submit" type="submit">Invite</Button.button>
      </form>
    </div>
    """
  end
end
