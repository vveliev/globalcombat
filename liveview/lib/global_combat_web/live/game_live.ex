defmodule GlobalCombatWeb.GameLive do
  @moduledoc """
  The game board (GIF-30) — replaces `Views/Game/Index.cshtml` + `Views/Game/_PlayerList.cshtml`
  and the `Web/wwwroot/Main.js`/`Global.js`/`jquery.signalR-0.5.1` client stack that kept them
  live. Mounted at `/Game-:id` (see `router.ex`); `/Game-:id/:action` (Invite/Kick/etc.) stays
  on the legacy `GameController` stub — out of scope here, see this ticket's follow-ups.

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

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]

  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.Components.Boutique.Input
  alias GlobalCombatWeb.Components.Boutique.Layouts.GameLayout
  alias GlobalCombatWeb.Components.Boutique.StatusPill

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
       |> assign(:chat_text, "")
       |> assign(:selected_area, nil)
       |> assign(:target_area, nil)
       |> assign(:order_amount, "")
       |> refresh_view()}
    else
      {:ok, socket |> put_flash(:error, "Game not found.") |> push_navigate(to: ~p"/")}
    end
  end

  defp refresh_view(socket) do
    account_id = socket.assigns.current_account && socket.assigns.current_account.id
    {status, view} = Games.player_view(socket.assigns.game_id, account_id)
    assign(socket, status: status, view: view)
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

  @impl true
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

  def handle_event("send_chat", %{"text" => text}, socket) do
    text = String.trim(text)

    case {text, require_account(socket)} do
      {"", _} ->
        {:noreply, socket}

      {_text, {:ok, account}} ->
        Games.send_chat(socket.assigns.game_id, account.id, account.name, text)
        {:noreply, assign(socket, :chat_text, "")}

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

  # GIF-111: click-to-select order composition, mirroring `Main.js`'s `OnClick`/
  # `ShowControl`/`SelectTarget` state machine (`ActiveArea`/`TargetArea` there ->
  # `:selected_area`/`:target_area` here). First click on a visible, owned area opens
  # the order panel in "assign" mode; a second click on a visible area adjacent to it
  # switches the panel to "transfer" (owned target) or "attack" (enemy target) mode.
  # Every other click (unowned first click, non-adjacent or hidden second click) is a
  # no-op, same as the original hiding non-adjacent territories entirely while a
  # source is active.
  def handle_event("select_area", %{"area" => area_str}, %{assigns: %{status: :playing}} = socket) do
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

  defp find_area(view, number), do: Enum.find(view.areas, &(&1.number == number))

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

  # --- rendering -------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <.site_chrome current_account={@current_account}>
      <GameLayout.game_layout id="game-board" phx-hook=".FocusManager">
        <:status>
          {status_line(assigns)}
        </:status>

        <:board>
          <Layouts.flash_group flash={@flash} />
          <%= case @status do %>
            <% :lobby -> %>
              {lobby(assigns)}
            <% :playing -> %>
              {board(assigns)}
          <% end %>
        </:board>

        <:players>
          <.player_list players={@view.players} viewer_number={@view.viewer_number} />
          <.chat
            messages={Map.get(@view, :messages, [])}
            chat_text={@chat_text}
            logged_in={!!@current_account}
          />
        </:players>
      </GameLayout.game_layout>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusManager">
        // Join/Start/End Turn/Force Turn all swap out significant subtrees
        // (lobby -> board, a button disappearing once its action no longer
        // applies). LiveView's morphdom patch drops focus to <body> when the
        // focused element is removed — this restores it to the game layout's
        // stable :status landmark (GameLayout, marked data-focus-landmark) so
        // keyboard/screen-reader users don't lose their place (GIF-82).
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
    </.site_chrome>
    """
  end

  defp status_line(%{status: :lobby} = assigns) do
    ~H"""
    <span class="font-semibold">Waiting for players</span>
    <StatusPill.status_pill tone="waiting">
      {length(@view.players)}/{@view.max_players} joined
    </StatusPill.status_pill>
    """
  end

  defp status_line(%{status: :playing} = assigns) do
    ~H"""
    <span class="font-semibold">Turn {@view.turn}</span>
    <StatusPill.status_pill tone={if @view.ended, do: "done", else: "active"}>
      {if @view.ended, do: "Ended", else: "In progress"}
    </StatusPill.status_pill>
    <span :if={@view.is_fogged} class="text-text-muted">Fog of war</span>
    """
  end

  defp lobby(assigns) do
    ~H"""
    <div class="flex flex-col gap-[var(--space-4)]">
      <h1 class="text-lg font-semibold">Game {@game_id}</h1>
      <ul class="flex flex-col gap-[var(--space-2)]">
        <li :for={p <- @view.players}>Player {p.number}: {p.name}</li>
      </ul>
      <div class="flex gap-[var(--space-3)]">
        <Button.button
          :if={@view.viewer_number == nil}
          phx-click="join"
          disabled={length(@view.players) >= @view.max_players}
        >
          Join
        </Button.button>
        <Button.button
          :if={@view.viewer_number == 1}
          intent="primary"
          phx-click="start"
          disabled={length(@view.players) < 2}
        >
          Start Game
        </Button.button>
      </div>
    </div>
    """
  end

  defp board(assigns) do
    ~H"""
    <div class="flex flex-wrap items-start gap-[var(--space-4)]">
      <div class="relative" style="width: 800px; height: 480px;">
        <.area
          :for={area <- @view.areas}
          area={area}
          map_name={@view.map_name}
          players={@view.players}
          selected_area={@selected_area}
          target_area={@target_area}
        />
      </div>
      <.region_bonuses map_name={@view.map_name} />
      <.order_panel
        :if={@selected_area}
        view={@view}
        selected_area={@selected_area}
        target_area={@target_area}
        order_amount={@order_amount}
      />
    </div>
    <.board_table areas={@view.areas} players={@view.players} />
    <div :if={@view.viewer_number} class="mt-[var(--space-4)]">
      <Button.button :if={!my_player(@view).done} phx-click="done">End Turn</Button.button>
      <span :if={my_player(@view).done} class="text-text-muted">Waiting on other players…</span>
      <Button.button intent="neutral" phx-click="force_turn">Force Turn</Button.button>
    </div>
    """
  end

  defp my_player(view), do: Enum.find(view.players, &(&1.number == view.viewer_number))

  attr :area, :map, required: true
  attr :map_name, :atom, required: true
  attr :players, :list, required: true
  attr :selected_area, :any, required: true
  attr :target_area, :any, required: true

  defp area(assigns) do
    ~H"""
    <span style={"position: absolute; left: #{@area.x}px; top: #{@area.y}px; width: #{@area.width}px; height: #{@area.height}px;"}>
      <button
        type="button"
        phx-click="select_area"
        phx-value-area={@area.number}
        disabled={!@area.visible}
        aria-pressed={@area.number == @selected_area or @area.number == @target_area}
        class={[
          "block appearance-none border-0 bg-transparent p-0 m-0",
          "focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring",
          @area.visible && "cursor-pointer",
          @area.number == @selected_area &&
            "outline outline-2 outline-offset-2 outline-focus-ring",
          @area.number == @target_area && "outline outline-2 outline-offset-2 outline-danger"
        ]}
      >
        <img
          src={"/maps/#{@map_name}/#{@area.tech_name}#{owner_color(@area.owner_number)}.gif"}
          width={@area.width}
          height={@area.height}
          alt={"#{@area.tech_name}, owned by #{owner_name(@players, @area.owner_number) || "unclaimed"}"}
        />
      </button>
      <span
        :if={@area.armies}
        class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 text-white font-bold [text-shadow:-1px_-1px_0_#000,1px_-1px_0_#000,-1px_1px_0_#000,1px_1px_0_#000] pointer-events-none"
      >
        {@area.armies}
      </span>
    </span>
    """
  end

  # GIF-111's order-composition panel — LiveView equivalent of `Main.js`'s
  # `EntryForm`/`ActionMessage`/`AmountInput`/`ActionSubmit`. `:assign` (no target
  # picked yet) offers Assign + Unassign (only if there's something pending to undo);
  # `:transfer`/`:attack` (a target picked) offer a single verb button matching
  # `SelectTarget`'s owned-vs-enemy branch.
  attr :view, :map, required: true
  attr :selected_area, :integer, required: true
  attr :target_area, :any, required: true
  attr :order_amount, :string, required: true

  defp order_panel(assigns) do
    source = find_area(assigns.view, assigns.selected_area)
    target = assigns.target_area && find_area(assigns.view, assigns.target_area)
    mode = order_mode(assigns.view, target)

    assigns = assign(assigns, source: source, target: target, mode: mode)

    ~H"""
    <Card.card class="min-w-[16rem]">
      <:header>{order_panel_title(@mode, @target)}</:header>
      <form phx-submit="submit_order" class="flex flex-col gap-[var(--space-3)]">
        <Input.input
          id="order-amount"
          name="amount"
          type="number"
          min="0"
          label="Armies"
          value={@order_amount}
        />
        <div class="flex flex-wrap gap-[var(--space-2)]">
          <Button.button type="submit" intent="primary">
            {order_submit_label(@mode)}
          </Button.button>
          <Button.button
            :if={(@mode == :assign and @source) && @source.pending_armies > 0}
            type="button"
            intent="neutral"
            phx-click="unassign_order"
          >
            Unassign
          </Button.button>
          <Button.button type="button" intent="neutral" phx-click="cancel_order">
            Cancel
          </Button.button>
        </div>
      </form>
    </Card.card>
    """
  end

  defp order_mode(_view, nil), do: :assign

  defp order_mode(view, target),
    do: if(target.owner_number == view.viewer_number, do: :transfer, else: :attack)

  defp order_panel_title(:assign, _target), do: "Assign new armies or select a target area"
  defp order_panel_title(:transfer, target), do: "Transfer how many armies to #{target.name}?"
  defp order_panel_title(:attack, target), do: "Attack #{target.name} with how many armies?"

  defp order_submit_label(:assign), do: "Assign"
  defp order_submit_label(:transfer), do: "Transfer"
  defp order_submit_label(:attack), do: "Attack"

  # Player-facing rule info (GIF-103): every region's control bonus, sourced
  # from the same `MapInfo.regions/1` the board's areas/adjacency already
  # come from rather than hardcoded per-map text, so a future map addition
  # doesn't need a matching edit here.
  attr :map_name, :atom, required: true

  defp region_bonuses(assigns) do
    assigns = assign(assigns, :regions, MapInfo.regions(assigns.map_name))

    ~H"""
    <Card.card class="min-w-[16rem]">
      <:header>Region Bonuses</:header>
      <ul class="flex flex-col gap-[var(--space-1)] text-sm">
        <li
          :for={{_number, name, _num_areas, army_bonus} <- @regions}
          class="flex items-center justify-between gap-[var(--space-3)]"
        >
          <span>{name}</span>
          <span class="font-semibold">{army_bonus}</span>
        </li>
      </ul>
    </Card.card>
    """
  end

  # White text alone doesn't meet WCAG 1.4.3 against every owner_color/1
  # background — Player.GetColor()'s #FFE45F (owner 3) measures 1.27:1 and
  # #D45D00 (owner 4) measures 3.91:1 against white, both below the 4.5:1
  # (normal) / 3:1 (large) thresholds. The black outline above guarantees
  # legibility independent of tile color, including future map/color
  # additions (GIF-83).
  defp owner_color(nil), do: 0
  defp owner_color(number), do: rem(number, 9)

  defp owner_name(_players, nil), do: nil

  defp owner_name(players, owner_number) do
    case Enum.find(players, &(&1.number == owner_number)) do
      %{name: name} -> name
      nil -> nil
    end
  end

  # Non-visual equivalent of the pixel-positioned board (GIF-81, WCAG 1.3.1): the
  # `<div>` above conveys territory/owner/army-count/adjacency purely through
  # image position and color, which is meaningless to a screen reader in DOM
  # order. This `sr-only` table (same pattern as BarChart/LineChart's fallback
  # table) carries the identical, already fog-of-war-filtered `@view.areas` data
  # as an ordered, navigable structure instead — visually hidden, never
  # `aria-hidden`, so assistive tech can still read it.
  #
  # Owner/army text reuses `owner_name/2`'s "unclaimed" fallback verbatim rather
  # than distinguishing "hidden by fog" from "actually unclaimed": area/1's alt
  # text makes that same choice (GIF-79), and diverging here would hand a screen
  # reader user more information than a sighted player looking at the same
  # neutral-colored sprite ever gets — a fairness leak, not just an inconsistency.
  # Adjacency, unlike owner/armies, is static map topology every viewer already
  # sees rendered on the board regardless of fog, so it's listed in full.
  attr :areas, :list, required: true
  attr :players, :list, required: true

  defp board_table(assigns) do
    assigns = assign(assigns, :area_names, Map.new(assigns.areas, &{&1.number, &1.name}))

    ~H"""
    <table class="sr-only">
      <caption>Board state: territory, owner, armies, and adjacency</caption>
      <thead>
        <tr>
          <th scope="col">Territory</th>
          <th scope="col">Owner</th>
          <th scope="col">Armies</th>
          <th scope="col">Adjacent to</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={area <- @areas}>
          <th scope="row">{area.name}</th>
          <td>{owner_name(@players, area.owner_number) || "unclaimed"}</td>
          <td>{area.armies || "—"}</td>
          <td>{adjacent_names(area, @area_names)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp adjacent_names(area, area_names) do
    area.adjacent
    |> Enum.map(&Map.fetch!(area_names, &1))
    |> Enum.join(", ")
  end

  attr :players, :list, required: true
  attr :viewer_number, :any, required: true

  defp player_list(assigns) do
    ~H"""
    <ul aria-live="polite" class="flex flex-col gap-[var(--space-2)]">
      <li :for={p <- @players} class="flex items-center justify-between gap-[var(--space-2)]">
        <span class={p.number == @viewer_number && "font-semibold"}>{p.name}</span>
        <span class="flex items-center gap-[var(--space-2)]">
          <span :if={!p.eliminated && p.armies} class="text-text-muted">
            {p.armies} ({p.areas})
          </span>
          <span :if={p.eliminated} class="text-text-muted">place {p.place}</span>
          <StatusPill.status_pill :if={!p.eliminated} tone={if p.done, do: "done", else: "waiting"}>
            {if p.done, do: "Done", else: "Thinking"}
          </StatusPill.status_pill>
        </span>
      </li>
    </ul>
    """
  end

  attr :messages, :list, required: true
  attr :chat_text, :string, required: true
  attr :logged_in, :boolean, required: true

  defp chat(assigns) do
    ~H"""
    <div class="mt-[var(--space-4)] flex flex-col gap-[var(--space-2)]">
      <form :if={@logged_in} phx-submit="send_chat" class="flex gap-[var(--space-2)]">
        <input
          type="text"
          name="text"
          value={@chat_text}
          placeholder="Send a message."
          class="flex-1 rounded border border-border px-[var(--space-2)]"
        />
        <Button.button type="submit">Send</Button.button>
      </form>
      <ul aria-live="polite" class="flex flex-col-reverse gap-[var(--space-1)] text-sm">
        <li :for={m <- @messages}>
          <span class="font-semibold">{m.source_name}:</span> {m.text}
        </li>
      </ul>
    </div>
    """
  end
end
