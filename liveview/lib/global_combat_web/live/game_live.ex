defmodule GlobalCombatWeb.GameLive do
  @moduledoc """
  The game page — replaces `Views/Game/Index.cshtml` + `Views/Game/_PlayerList.cshtml`
  and the `Web/wwwroot/Main.js`/`Global.js`/`jquery.signalR-0.5.1` client stack that kept them
  live. Mounted at `/Game-:id` (see `router.ex`). `/Game-:id/:action` (the legacy AJAX action
  path) stays on the `GameController` stub — this rewrite has no legacy AJAX callers left to
  serve, so the lobby's Invite/Quit/Kick are wired here instead, as `phx-click`/`phx-submit`
  events consistent with join/start/done, rather than reviving that controller path.

  This module owns the socket: mount, the realtime `handle_info/2` callbacks, every
  `handle_event/3`, and the top-level `render/1` that composes the page from stateless
  function components under `GlobalCombatWeb.GameLive.*`:

    * `StatusBar` — the status strip (turn/lobby line, lens switch, Fit, full screen)
    * `TurnResults` — the last-turn replay controls and the accessible results list
    * `Lobby` — the pre-start roster, Join/Start/Quit and invite form
    * `Board` — the map, its game-over caption and the screen-reader board table
    * `GameOver` — the finished-game panel and the outcome wording
    * `Dock` — the stage-mode order panel and turn controls
    * `PlayersList`, `PlayersExtras`, `Chat` — the players drawer/rail

  Realtime updates arrive over `GlobalCombat.Games.PubSub` instead of a SignalR hub connection:
  every socket subscribes to its game's board topic, and — once resolved to a seated player —
  its own private account topic, then reacts to the five broadcast events in `handle_info/2`
  below (`GlobalCombat.Games.PubSub`'s moduledoc has the full group/event -> topic/message
  mapping table this mirrors).

  All game state reaches this module through `GlobalCombat.Games.Live.player_view/2`, which
  returns an already fog-of-war-filtered `%GlobalCombat.Games.PlayerView{}` — see that module's
  moduledoc for why this LiveView must never call `GlobalCombat.Games.Server`/
  `GlobalCombat.Engine.Game` directly, no matter how convenient a shortcut looks.
  """

  use GlobalCombatWeb, :live_view

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1, sidebar_links: 1]
  import GlobalCombatWeb.GameLive.ViewHelpers, only: [find_area: 2, my_player: 1]

  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Layouts.GameLayout
  alias GlobalCombatWeb.GameLive.Board
  alias GlobalCombatWeb.GameLive.Chat
  alias GlobalCombatWeb.GameLive.Dock
  alias GlobalCombatWeb.GameLive.GameOver
  alias GlobalCombatWeb.GameLive.Lobby
  alias GlobalCombatWeb.GameLive.PlayersExtras
  alias GlobalCombatWeb.GameLive.PlayersList
  alias GlobalCombatWeb.GameLive.Replay
  alias GlobalCombatWeb.GameLive.StatusBar

  @impl true
  def mount(%{"id" => id_param}, _session, socket) do
    case Integer.parse(id_param) do
      {game_id, ""} -> mount_game(game_id, socket)
      _ -> {:ok, socket |> put_flash(:error, "Not Found") |> push_navigate(to: ~p"/")}
    end
  end

  defp mount_game(game_id, socket) do
    if Games.game_exists?(game_id) do
      if connected?(socket) do
        Games.subscribe(game_id)

        if account = socket.assigns.current_account do
          Games.subscribe_account(account.id)
        end
      end

      {:ok,
       socket
       |> assign(:game_id, game_id)
       |> assign(:chat_form, to_form(%{"text" => ""}))
       |> assign(:invite_login, "")
       |> assign(:selected_area, nil)
       |> assign(:target_area, nil)
       |> assign(:order_amount, "")
       |> assign(:lens, :owner)
       |> refresh_view()}
    else
      {:ok, socket |> put_flash(:error, "Game not found.") |> push_navigate(to: ~p"/")}
    end
  end

  defp refresh_view(socket) do
    account_id = socket.assigns.current_account && socket.assigns.current_account.id

    case Games.player_view(socket.assigns.game_id, account_id) do
      {:error, :not_found} ->
        # The lobby was deleted out from under this view — the last seat quit (port of
        # `GameServer.KillGame`), so there is nothing left to render; send everyone home.
        socket
        |> put_flash(:info, "That game is no longer open.")
        |> push_navigate(to: ~p"/")

      {:playing, %{ended: true} = view} ->
        # A game that just ended can't leave a stale click-to-select in progress —
        # without this, `order_panel` (guarded on `@selected_area`) could still be
        # showing "Assign new armies" over a board with no more turns to take.
        socket |> assign(status: :playing, view: view) |> clear_selection()

      {status, view} ->
        assign(socket, status: status, view: view)
    end
  end

  # --- realtime events (GlobalCombat.Games.PubSub) ------------------------

  @impl true
  def handle_info(:reload, socket) do
    previous_turn = playing_turn(socket.assigns)
    socket = refresh_view(socket)

    # An order submission (assign/transfer/attack/unassign) also broadcasts :reload —
    # to every seat, not just the one that submitted it — so this can't unconditionally
    # clear the local selection panel: that would let one player's order wipe another
    # player's in-progress click-to-select state out from under them. Only a turn
    # actually resolving invalidates a pending selection (orders don't survive
    # `run_turn`'s `clear_commands/1`, and area ownership can only change there).
    socket =
      if playing_turn(socket.assigns) != previous_turn, do: clear_selection(socket), else: socket

    {:noreply, socket}
  end

  def handle_info({:add_message, message}, %{assigns: %{status: :playing}} = socket) do
    view = %{
      socket.assigns.view
      | messages: Enum.take([message | socket.assigns.view.messages], 150)
    }

    {:noreply, assign(socket, :view, view)}
  end

  def handle_info({:add_message, _message}, socket), do: {:noreply, socket}

  def handle_info({:set_done, player_number}, %{assigns: %{status: :playing}} = socket) do
    players =
      Enum.map(socket.assigns.view.players, fn
        %{number: ^player_number} = p -> %{p | done: true}
        p -> p
      end)

    {:noreply, assign(socket, :view, %{socket.assigns.view | players: players})}
  end

  def handle_info({:set_done, _player_number}, socket), do: {:noreply, socket}

  def handle_info({:receive_message, _source_id, source_name, text}, socket) do
    {:noreply, put_flash(socket, :info, "Message from #{source_name}: #{text}")}
  end

  def handle_info({:notification, title, text, _target_uri}, socket) do
    body = if text in [nil, ""], do: title, else: "#{title} — #{text}"
    {:noreply, put_flash(socket, :info, body)}
  end

  defp playing_turn(%{status: :playing, view: view}), do: view.turn
  defp playing_turn(_assigns), do: nil

  # --- user actions --------------------------------------------------------

  # A finished game takes no more turns or orders. The game server already refuses them; this
  # just keeps a crafted event (the controls are gone from the page) from reaching it at all.
  @ended_game_events ~w(done force_turn submit_order unassign_order change_amount step_amount max_amount)

  @impl true
  def handle_event(event, _params, %{assigns: %{status: :playing, view: %{ended: true}}} = socket)
      when event in @ended_game_events,
      do: {:noreply, socket}

  def handle_event("join", _params, socket) do
    case require_account(socket) do
      {:ok, account} ->
        Games.join(socket.assigns.game_id, account.id, account.name)
        {:noreply, refresh_view(socket)}

      :error ->
        {:noreply, put_flash(socket, :error, "You must be logged in to join the game.")}
    end
  end

  def handle_event("start", _params, socket) do
    with {:ok, account} <- require_account(socket),
         :ok <- Games.start_game(socket.assigns.game_id, account.id) do
      {:noreply, refresh_view(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("invite", %{"login" => login}, socket) do
    login = String.trim(login)

    case {login, require_account(socket)} do
      {"", _} ->
        {:noreply, socket}

      {_login, {:ok, account}} ->
        case Games.invite_many(socket.assigns.game_id, account.id, login) do
          results when is_list(results) ->
            {:noreply, invite_flashes(socket, results)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, invite_error_message(reason, login))}
        end

      {_login, :error} ->
        {:noreply, socket}
    end
  end

  def handle_event("quit", _params, socket) do
    case require_account(socket) do
      {:ok, account} ->
        case Games.quit(socket.assigns.game_id, account.id) do
          # A lobby emptied by this quit is deleted server-side, so refresh_view/1 itself
          # navigates home; a mid-play quit just re-renders the board as eliminated.
          :ok ->
            {:noreply, refresh_view(socket)}

          {:error, :tourney_game} ->
            {:noreply, put_flash(socket, :error, "Unable to quit a tournament game.")}

          {:error, _reason} ->
            {:noreply, socket}
        end

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("kick", %{"player_number" => player_number}, socket) do
    with {:ok, account} <- require_account(socket),
         {player_number, ""} <- Integer.parse(player_number) do
      Games.kick(socket.assigns.game_id, account.id, player_number)
      {:noreply, refresh_view(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("send_chat", %{"text" => text}, socket) do
    text = String.trim(text)

    case {text, require_account(socket)} do
      {"", _} ->
        {:noreply, socket}

      {_text, {:ok, account}} ->
        Games.send_chat(socket.assigns.game_id, account.id, account.name, text)
        {:noreply, assign(socket, :chat_form, to_form(%{"text" => ""}))}

      {_text, :error} ->
        {:noreply, socket}
    end
  end

  def handle_event("done", _params, socket) do
    with {:ok, account} <- require_account(socket) do
      Games.set_done(socket.assigns.game_id, account.id)
    end

    {:noreply, socket}
  end

  def handle_event("force_turn", _params, socket) do
    with {:ok, account} <- require_account(socket) do
      Games.force_turn(socket.assigns.game_id, account.id)
    end

    {:noreply, socket}
  end

  # Click-to-select order composition, mirroring `Main.js`'s `OnClick`/
  # `ShowControl`/`SelectTarget` state machine (`ActiveArea`/`TargetArea` there ->
  # `:selected_area`/`:target_area` here). First click on a visible, owned area opens
  # the order panel in "assign" mode; a second click on a visible area adjacent to it
  # switches the panel to "transfer" (owned target) or "attack" (enemy target) mode.
  # Every other click (unowned first click, non-adjacent or hidden second click) is a
  # no-op, same as the original hiding non-adjacent territories entirely while a
  # source is active.
  def handle_event(
        "select_area",
        %{"area" => area_str},
        %{assigns: %{status: :playing, view: %{ended: false}}} = socket
      ) do
    case Integer.parse(area_str) do
      {area_number, ""} ->
        case find_area(socket.assigns.view, area_number) do
          nil -> {:noreply, socket}
          area -> {:noreply, handle_area_click(socket, area)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_area", _params, socket), do: {:noreply, socket}

  # An order arrow's click must reopen *its own* queued order for
  # editing, not run through select_area's click-to-target heuristic — that heuristic
  # reads whatever is already selected as context (a second click either sets a target
  # or is a no-op), so it silently mistreated the arrow's source as a *new* target when
  # another area was already selected, and did nothing at all when the arrow's own
  # source was already selected. This event instead sets selected/target/amount
  # directly from the area's own `order`, unconditionally overriding any unrelated
  # in-progress selection.
  def handle_event(
        "select_order",
        %{"area" => area_str},
        %{assigns: %{status: :playing, view: %{ended: false}}} = socket
      ) do
    case Integer.parse(area_str) do
      {area_number, ""} ->
        case find_area(socket.assigns.view, area_number) do
          %{order: order} = area when not is_nil(order) ->
            {:noreply,
             assign(socket,
               selected_area: area.number,
               target_area: order.target,
               order_amount: to_string(order.amount)
             )}

          _ ->
            {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_order", _params, socket), do: {:noreply, socket}

  def handle_event("submit_order", %{"amount" => amount_str}, socket) do
    with {:ok, account} <- require_account(socket),
         source when not is_nil(source) <- socket.assigns.selected_area,
         amount when amount >= 0 <- parse_amount(amount_str) do
      submit_order(socket, account, source, socket.assigns.target_area, amount)
      {:noreply, clear_selection(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unassign_order", _params, socket) do
    with {:ok, account} <- require_account(socket),
         source when not is_nil(source) <- socket.assigns.selected_area do
      Games.unassign(socket.assigns.game_id, account.id, source)
      {:noreply, clear_selection(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_order", _params, socket), do: {:noreply, clear_selection(socket)}

  # The amount field, stepper and Max only ever rewrite the draft `order_amount`;
  # nothing reaches the game server until `submit_order`, which validates as before.
  # `change_amount` keeps the draft in step with what was typed, so a step or Max
  # after typing starts from the typed number rather than the prefill.
  def handle_event("change_amount", %{"amount" => amount_str}, socket),
    do: {:noreply, assign(socket, :order_amount, amount_str)}

  def handle_event("step_amount", %{"delta" => delta_str}, socket) do
    case Integer.parse(to_string(delta_str)) do
      {delta, ""} ->
        amount = max(parse_amount(socket.assigns.order_amount), 0) + delta
        {:noreply, assign(socket, :order_amount, to_string(max(amount, 0)))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("max_amount", _params, socket) do
    case max_order_amount(socket.assigns) do
      nil -> {:noreply, socket}
      amount -> {:noreply, assign(socket, :order_amount, to_string(max(amount, 0)))}
    end
  end

  # The map lens is a per-viewer display preference, not game state —
  # it lives only in this socket's assigns, same as :selected_area/:target_area,
  # never touching `PlayerView`.
  def handle_event("set_lens", %{"lens" => lens}, socket) do
    case lens do
      "owner" -> {:noreply, assign(socket, :lens, :owner)}
      "region" -> {:noreply, assign(socket, :lens, :region)}
      "frontier" -> {:noreply, assign(socket, :lens, :frontier)}
      _ -> {:noreply, socket}
    end
  end

  defp handle_area_click(socket, area) do
    view = socket.assigns.view

    cond do
      is_nil(socket.assigns.selected_area) ->
        if area.visible and area.owner_number == view.viewer_number do
          assign(socket,
            selected_area: area.number,
            target_area: nil,
            order_amount: to_string(my_player(view).unassigned_armies)
          )
        else
          socket
        end

      area.number == socket.assigns.selected_area ->
        socket

      true ->
        source = find_area(view, socket.assigns.selected_area)

        if (source && area.visible) and area.number in source.adjacent do
          assign(socket,
            target_area: area.number,
            order_amount: to_string(max(source.armies - 1, 0))
          )
        else
          socket
        end
    end
  end

  defp submit_order(socket, account, source, nil, amount) do
    Games.assign(socket.assigns.game_id, account.id, source, amount)
  end

  defp submit_order(socket, account, source, target, amount) do
    target_area = find_area(socket.assigns.view, target)

    if target_area && target_area.owner_number == socket.assigns.view.viewer_number do
      Games.transfer(socket.assigns.game_id, account.id, source, target, amount)
    else
      Games.attack(socket.assigns.game_id, account.id, source, target, amount)
    end
  end

  # Assign mode tops out at the viewer's unassigned pool; transfer and attack at
  # the source's whole stack (the engine clamps to armies - 1 when it resolves).
  defp max_order_amount(%{status: :playing, selected_area: selected} = assigns)
       when not is_nil(selected) do
    view = assigns.view

    case {find_area(view, selected), assigns.target_area, my_player(view)} do
      {nil, _target, _me} -> nil
      {_source, nil, nil} -> nil
      {_source, nil, me} -> me.unassigned_armies
      {source, _target, _me} -> source.armies
    end
  end

  defp max_order_amount(_assigns), do: nil

  defp parse_amount(amount_str) do
    case Integer.parse(String.trim(to_string(amount_str))) do
      {amount, _} when amount >= 0 -> amount
      _ -> -1
    end
  end

  defp clear_selection(socket),
    do: assign(socket, selected_area: nil, target_area: nil, order_amount: "")

  defp require_account(socket) do
    case socket.assigns.current_account do
      nil -> :error
      account -> {:ok, account}
    end
  end

  # The invite box takes a comma/newline separated list (`Games.invite_many/3`): one info flash
  # naming everyone invited, one error flash with a line per login that failed.
  defp invite_flashes(socket, results) do
    invited = for {_login, {:ok, invitee}} <- results, do: invitee.name

    errors =
      for {login, {:error, reason}} <- results, do: invite_error_message(reason, login)

    socket =
      if invited == [] do
        socket
      else
        socket
        |> put_flash(:info, "Invited #{Enum.join(invited, ", ")}.")
        |> assign(:invite_login, "")
        |> refresh_view()
      end

    if errors == [], do: socket, else: put_flash(socket, :error, Enum.join(errors, " "))
  end

  defp invite_error_message(:account_not_found, login), do: "No account found for \"#{login}\"."
  defp invite_error_message(:cannot_invite_self, _login), do: "You can't invite yourself."

  defp invite_error_message(:already_playing, login),
    do: "#{login} is already in this game."

  defp invite_error_message(:already_invited, login),
    do: "#{login} has already been invited to this game."

  defp invite_error_message(:not_in_lobby, _login),
    do: "Invites can only be sent before the game starts."

  defp invite_error_message(_reason, _login), do: "Unable to send that invite."

  # --- rendering -------------------------------------------------------------

  # Computed once per render (not per sub-template) so the status strip's replay
  # controls and the board's WorldMap + results list always agree on the same
  # steps — see `GameLive.Replay.steps/4` for the shape.
  @impl true
  def render(%{status: :playing} = assigns) do
    assigns = assign(assigns, :replay_steps, replay_steps(assigns.view))
    render_game(assigns)
  end

  def render(assigns), do: render_game(assigns)

  defp replay_steps(view),
    do: Replay.steps(view.last_turn_events, view.areas, view.players, view.map_name)

  # Computed once per render and threaded through `assigns` to both the `:status` slot
  # (the status strip's ended announcement) and the `:board` slot (`GameOver.game_over/1`) —
  # the winner and the viewer's own seat each used to be looked up twice per render (once per
  # slot, again inside the game-over panel) since both slots render from the same top-level
  # `assigns` but neither could see the other's local computation.
  defp maybe_assign_outcome(%{status: :playing} = assigns),
    do: assign(assigns, GameOver.outcome(assigns.view))

  defp maybe_assign_outcome(assigns), do: assigns

  # Stage mode (GameLayout's `stage` attr) and SiteChrome's matching `immersive`
  # only apply while a turn is actually in progress — the lobby and the
  # finished-game screen read better stacked (GameLayout's existing
  # `players_first` flip already covers the latter), and neither is short-lived
  # enough to be worth swallowing the whole viewport for
  # (`docs/mobile-battle-mode.md` §3, "Scope of stage mode").
  defp stage?(%{status: :playing, view: %{ended: false}}), do: true
  defp stage?(_assigns), do: false

  defp render_game(assigns) do
    assigns = maybe_assign_outcome(assigns)
    assigns = assign(assigns, :stage, stage?(assigns))

    ~H"""
    <.site_chrome
      current_account={@current_account}
      current_path={assigns[:current_path]}
      page_title={"Game #{@game_id}"}
      immersive={@stage}
    >
      <%!-- The keyboard-inset wrapper (.StageViewport, below): it contains the
      whole shell — board, dock and drawer — so it sees focus land in the dock's
      amount field, and overriding --size-stage here resizes the shell. --%>
      <div id="game-viewport" phx-hook=".StageViewport" data-stage={@stage}>
        <GameLayout.game_layout
          id="game-board"
          players_first={@status == :playing && @view.ended}
          stage={@stage}
          phx-hook=".FocusManager"
        >
          <:status>
            <StatusBar.status_bar
              status={@status}
              view={@view}
              lens={@lens}
              replay_steps={assigns[:replay_steps] || []}
              headline={assigns[:headline]}
              outcome={assigns[:outcome]}
            />
          </:status>

          <:board>
            <%!-- h-full: stage mode's <main> (GameLayout) is the definite-height grid
          row the board's own figure/`.world-map`/<svg> height chain needs
          (`GameLive.Board`) — without it here, this wrapper's own
          auto-by-default height would break that chain one level up. Outside
          stage mode <main> has no definite height either, so this resolves to
          plain `auto` there (CSS percentage-height-of-indefinite-ancestor
          rule) — a no-op. --%>
            <div id="game-board-surface" class="h-full">
              <Layouts.flash_group flash={@flash} />
              <%= case @status do %>
                <% :lobby -> %>
                  <Lobby.lobby game_id={@game_id} view={@view} invite_login={@invite_login} />
                <% :playing -> %>
                  <Board.board
                    game_id={@game_id}
                    view={@view}
                    stage={@stage}
                    selected_area={@selected_area}
                    target_area={@target_area}
                    lens={@lens}
                    replay_steps={@replay_steps}
                    winner={@winner}
                    headline={@headline}
                    outcome={@outcome}
                  />
              <% end %>
            </div>
          </:board>

          <%!-- Seated players only: a spectator has no orders to compose and no
        turn to end, so an always-present slot would render an empty,
        bordered "Actions" sheet for them. --%>
          <:dock :if={@stage && @view.viewer_number}>
            <Dock.dock
              view={@view}
              selected_area={@selected_area}
              target_area={@target_area}
              order_amount={@order_amount}
            />
          </:dock>

          <:players>
            <PlayersList.player_list
              players={@view.players}
              viewer_number={@view.viewer_number}
              status={@status}
              ended={@status == :playing and @view.ended}
              map_name={Map.get(@view, :map_name)}
            />
            <%= if @status == :playing do %>
              <PlayersExtras.players_extras view={@view} replay_steps={@replay_steps} />
            <% end %>
            <Chat.chat
              messages={Map.get(@view, :messages, [])}
              chat_form={@chat_form}
              logged_in={!!@current_account}
            />
            <%!-- Below lg only: there Quit lives in the drawer so it can't be hit
          by accident from the dock (docs/mobile-battle-mode.md §2, rule 3).
          :players renders once, inside the one <dialog> GameLayout shows as
          the mobile drawer and the lg: rail alike, so lg:hidden keeps the
          desktop rail unchanged — above lg Quit stays in #turn-controls
          (`GameLive.Dock`), where it has always been ("above lg nothing changes"). --%>
            <Button.button
              :if={
                @status == :playing && @view.viewer_number && !@view.ended &&
                  !my_player(@view).eliminated
              }
              id="quit-button"
              intent="danger"
              phx-click="quit"
              class="mt-[var(--space-4)] lg:hidden"
            >
              Quit
            </Button.button>
            <div class="mt-[var(--space-4)] flex flex-col gap-[var(--space-2)] border-t border-border pt-[var(--space-4)] text-sm lg:hidden">
              <.sidebar_links
                current_account={@current_account}
                current_path={assigns[:current_path]}
              />
            </div>
          </:players>
        </GameLayout.game_layout>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusManager">
        // Join/Start/End Turn/Force Turn all swap out significant subtrees
        // (lobby -> board, a button disappearing once its action no longer
        // applies). LiveView's morphdom patch drops focus to <body> when the
        // focused element is removed — this restores it to the game layout's
        // stable :status landmark (GameLayout, marked data-focus-landmark) so
        // keyboard/screen-reader users don't lose their place (WCAG 2.4.3).
        export default {
          beforeUpdate() {
            const active = document.activeElement
            this.focusedBeforeUpdate = this.el.contains(active) ? active : null
          },
          updated() {
            const lost = this.focusedBeforeUpdate
            this.focusedBeforeUpdate = null
            if (lost && !document.body.contains(lost)) {
              this.el.querySelector("[data-focus-landmark]")?.focus()
            }
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".StageViewport">
        // iOS Safari's soft keyboard shrinks the visual viewport but not the
        // layout viewport, so the stage shell (`h-[var(--size-stage)]`, i.e.
        // 100dvh) keeps its full height and the dock at its bottom — the
        // amount field and its Assign/Attack button — ends up under the
        // keyboard. While a text field inside the shell has focus below
        // `lg`, this sets `--size-stage` on this wrapper to
        // `visualViewport.height`, so the shell (and its dock) fits above
        // the keyboard (docs/mobile-battle-mode.md §2 rule 6, §4.6). Android
        // already resizes the layout (`interactive-widget=resizes-content`),
        // where the override simply matches. Cleared again once focus leaves
        // the field, above `lg`, and outside stage mode (`data-stage`).
        import {DESKTOP_QUERY} from "@/js/breakpoints"

        const TEXT_ENTRY =
          "input:not([type=button]):not([type=submit]):not([type=checkbox]):not([type=radio]), textarea"

        export default {
          mounted() {
            this.desktop = window.matchMedia(DESKTOP_QUERY)
            this.sync = () => this.syncHeight()
            // document.activeElement only settles after focusout has fired.
            this.onFocusOut = () => requestAnimationFrame(this.sync)
            window.visualViewport?.addEventListener("resize", this.sync)
            this.el.addEventListener("focusin", this.sync)
            this.el.addEventListener("focusout", this.onFocusOut)
            this.desktop.addEventListener("change", this.sync)
          },

          // A patch resets the style attribute the server never renders.
          updated() {
            this.syncHeight()
          },

          destroyed() {
            window.visualViewport?.removeEventListener("resize", this.sync)
            this.el.removeEventListener("focusin", this.sync)
            this.el.removeEventListener("focusout", this.onFocusOut)
            this.desktop.removeEventListener("change", this.sync)
          },

          pinned() {
            const active = document.activeElement
            return (
              this.el.dataset.stage !== undefined &&
              !this.desktop.matches &&
              !!window.visualViewport &&
              !!active &&
              this.el.contains(active) &&
              active.matches(TEXT_ENTRY)
            )
          },

          syncHeight() {
            if (this.pinned()) {
              this.el.style.setProperty("--size-stage", `${window.visualViewport.height}px`)
            } else {
              this.el.style.removeProperty("--size-stage")
            }
          }
        }
      </script>
    </.site_chrome>
    """
  end
end
