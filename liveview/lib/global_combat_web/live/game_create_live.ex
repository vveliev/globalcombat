defmodule GlobalCombatWeb.GameCreateLive do
  @moduledoc """
  Port of `Views/Game/Create.cshtml` + `GameController.Create` (GIF-30). Creates a
  `GlobalCombat.Games.Live` lobby and joins the creating account as player 1 (mirroring
  the original's `model.Join(Account.Id, ...)` right after `GameServer.SaveNewGame`),
  then redirects to the board.

  GIF-93: the form now exposes all 9 of the legacy settings — `GlobalCombat.Games.Server`
  already accepted `is_training`/`minimum_armies`/`turn_length_minutes` (this module's
  moduledoc just hadn't caught up to submit them). Training Mode additionally auto-joins
  the reserved "Computer" account (id 1, see `Engine.Game.reset_done_flags/1`) and forces
  `max_players` to 2, mirroring `GameController.Create`'s `if (model.IsTraining)` branches
  — without a second seat the lobby could never reach `Server.start_game/2`'s `>= 2` guard.

  Private Invite Only is UI-only for now: `Server` records `is_private` on the lobby, but
  nothing enforces it yet, since `GameController.Join`'s invite check depends on an invite
  list this port hasn't built (`GameLive`'s moduledoc tracks `/Game-:id/Invite` as the same
  pre-existing scope cut).
  """

  use GlobalCombatWeb, :live_view

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]

  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombatWeb.Components.Boutique.Button

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_account do
      {:ok,
       assign(socket,
         map_name: "original",
         max_players: 6,
         is_fogged: false,
         reverse_attack_order: false,
         is_non_random: false,
         is_training: false,
         turn_length_minutes: 1440,
         minimum_armies: 3,
         is_private: false
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be logged in to create a game.")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("create", params, socket) do
    account = socket.assigns.current_account
    is_training = params["is_training"] == "true"

    game_id =
      Games.create_game(%{
        map_name: String.to_existing_atom(params["map_name"]),
        max_players: if(is_training, do: 2, else: String.to_integer(params["max_players"])),
        is_fogged: params["is_fogged"] == "true",
        reverse_attack_order: params["reverse_attack_order"] == "true",
        is_non_random: params["is_non_random"] == "true",
        is_training: is_training,
        turn_length_minutes: String.to_integer(params["turn_length_minutes"]),
        minimum_armies: String.to_integer(params["minimum_armies"]),
        is_private: params["is_private"] == "true"
      })

    {:ok, 1} = Games.join(game_id, account.id, account.name)
    if is_training, do: {:ok, 2} = Games.join(game_id, 1, "Computer")

    {:noreply, push_navigate(socket, to: ~p"/Game-#{game_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.site_chrome current_account={@current_account}>
      <div class="mx-auto max-w-2xl p-[var(--space-4)]">
        <h1 class="text-lg font-semibold mb-[var(--space-4)]">Create a New Game</h1>

        <form phx-submit="create" class="flex flex-col gap-[var(--space-4)]">
          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_training" value="true" /> Training Mode
          </label>

          <label class="flex flex-col gap-[var(--space-1)]">
            Max Number of Players
            <select name="max_players" class="border border-border rounded px-[var(--space-2)]">
              <option :for={n <- 2..8} value={n} selected={n == 6}>{n}</option>
            </select>
          </label>

          <label class="flex flex-col gap-[var(--space-1)]">
            Map
            <select name="map_name" class="border border-border rounded px-[var(--space-2)]">
              <option value="original">World War I Era</option>
              <option value="elements">Battle of the Elements</option>
            </select>
          </label>

          <label class="flex flex-col gap-[var(--space-1)]">
            Turn Timeout Length
            <select
              name="turn_length_minutes"
              class="border border-border rounded px-[var(--space-2)]"
            >
              <option value="1">1 Minute</option>
              <option value="2">2 Minute</option>
              <option value="5">5 Minute</option>
              <option value="60">1 Hour</option>
              <option value="1440" selected>1 Day</option>
              <option value="4320">3 Day</option>
            </select>
            <span class="text-sm text-text-muted">
              When the force turn becomes available. Please force turn sparingly.
            </span>
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_fogged" value="true" /> Fog of War
          </label>

          <label class="flex flex-col gap-[var(--space-1)]">
            Minimum Army Bonus
            <select name="minimum_armies" class="border border-border rounded px-[var(--space-2)]">
              <option :for={n <- 0..5} value={n} selected={n == 3}>{n}</option>
            </select>
            <span class="text-sm text-text-muted">Minimum number of new armies given each turn.</span>
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="reverse_attack_order" value="true" /> Reverse Attack Order
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_non_random" value="true" /> Non-Random Attacks
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_private" value="true" /> Private Invite Only
          </label>

          <Button.button type="submit" intent="primary">Create Game</Button.button>
        </form>
      </div>
    </.site_chrome>
    """
  end
end
