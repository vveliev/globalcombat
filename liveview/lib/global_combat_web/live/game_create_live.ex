defmodule GlobalCombatWeb.GameCreateLive do
  @moduledoc """
  Port of `Views/Game/Create.cshtml` + `GameController.Create` (GIF-30). Creates a
  `GlobalCombat.Games.Live` lobby and joins the creating account as player 1 (mirroring
  the original's `model.Join(Account.Id, ...)` right after `GameServer.SaveNewGame`),
  then redirects to the board.

  Full parity with the legacy form (training mode, tournament linkage) is out of scope
  here — see `GlobalCombat.Games.Server`'s moduledoc for the `Start()`/persistence scope
  cut this whole feature makes; this form only exposes what a from-scratch lobby needs.
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
         is_non_random: false
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

    game_id =
      Games.create_game(%{
        map_name: String.to_existing_atom(params["map_name"]),
        max_players: String.to_integer(params["max_players"]),
        is_fogged: params["is_fogged"] == "true",
        reverse_attack_order: params["reverse_attack_order"] == "true",
        is_non_random: params["is_non_random"] == "true"
      })

    {:ok, 1} = Games.join(game_id, account.id, account.name)

    {:noreply, push_navigate(socket, to: ~p"/Game-#{game_id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.site_chrome current_account={@current_account}>
      <div class="mx-auto max-w-2xl p-[var(--space-4)]">
        <h1 class="text-lg font-semibold mb-[var(--space-4)]">Create a New Game</h1>

        <form phx-submit="create" class="flex flex-col gap-[var(--space-4)]">
          <label class="flex flex-col gap-[var(--space-1)]">
            Map
            <select name="map_name" class="border border-border rounded px-[var(--space-2)]">
              <option value="original">World War I Era</option>
              <option value="elements">Battle of the Elements</option>
            </select>
          </label>

          <label class="flex flex-col gap-[var(--space-1)]">
            Max Number of Players
            <select name="max_players" class="border border-border rounded px-[var(--space-2)]">
              <option :for={n <- 2..8} value={n} selected={n == 6}>{n}</option>
            </select>
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_fogged" value="true" /> Fog of War
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="reverse_attack_order" value="true" /> Reverse Attack Order
          </label>

          <label class="flex items-center gap-[var(--space-2)]">
            <input type="checkbox" name="is_non_random" value="true" /> Non-Random Attacks
          </label>

          <Button.button type="submit" intent="primary">Create Game</Button.button>
        </form>
      </div>
    </.site_chrome>
    """
  end
end
