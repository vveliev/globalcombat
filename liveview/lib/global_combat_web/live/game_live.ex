defmodule GlobalCombatWeb.GameLive do
  @moduledoc """
  The game board (GIF-30) — replaces `Views/Game/Index.cshtml` + `Views/Game/_PlayerList.cshtml`
  and the `Web/wwwroot/Main.js`/`Global.js`/`jquery.signalR-0.5.1` client stack that kept them
  live. Mounted at `/Game-:id` (see `router.ex`). `/Game-:id/:action` (the legacy AJAX action
  path) stays on the `GameController` stub — this rewrite has no legacy AJAX callers left to
  serve, so Invite/Quit/Kick (GIF-114) are wired here instead, as `phx-click`/`phx-submit`
  events consistent with join/start/done, rather than reviving that controller path.

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

  alias GlobalCombat.Engine.MapInfo
  alias GlobalCombat.Games.Live, as: Games
  alias GlobalCombatWeb.Components.Boutique.Button
  alias GlobalCombatWeb.Components.Boutique.Card
  alias GlobalCombatWeb.Components.Boutique.Input
  alias GlobalCombatWeb.Components.Boutique.Kicker
  alias GlobalCombatWeb.Components.Boutique.Layouts.GameLayout
  alias GlobalCombatWeb.Components.Boutique.SegmentedControl
  alias GlobalCombatWeb.Components.Boutique.StatusPill
  alias GlobalCombatWeb.GameLive.Hud
  alias GlobalCombatWeb.GameLive.Replay
  alias GlobalCombatWeb.GameLive.WorldMap

  @end_turn_arm_ms 3_000

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
       |> assign(:assign_history, [])
       |> assign(:end_turn_armed, false)
       |> assign(:end_turn_timer, nil)
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

      {:playing, view} ->
        socket
        |> assign(status: :playing, view: view)
        |> update(:assign_history, &Hud.reconcile_history(&1, view))

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
      if playing_turn(socket.assigns) != previous_turn,
        do: socket |> clear_selection() |> disarm_end_turn(),
        else: socket

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

  def handle_info(:disarm_end_turn, socket), do: {:noreply, disarm_end_turn(socket)}

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

  def handle_event("invite", %{"login" => login}, socket) do
    login = String.trim(login)

    case {login, require_account(socket)} do
      {"", _} ->
        {:noreply, socket}

      {_login, {:ok, account}} ->
        case Games.invite(socket.assigns.game_id, account.id, login) do
          {:ok, invitee} ->
            {:noreply,
             socket
             |> put_flash(:info, "Invited #{invitee.name}.")
             |> assign(:invite_login, "")
             |> refresh_view()}

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

    {:noreply, disarm_end_turn(socket)}
  end

  # Ending a turn with reinforcements still unplaced throws them away, so the
  # HUD's End Turn button sends this first instead of `done`: it arms the
  # button ("3 unplaced · tap again") for a few seconds, during which the
  # button's click is `done`.
  def handle_event("arm_end_turn", _params, socket) do
    socket = disarm_end_turn(socket)
    timer = Process.send_after(self(), :disarm_end_turn, @end_turn_arm_ms)
    {:noreply, assign(socket, end_turn_armed: true, end_turn_timer: timer)}
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
      target = socket.assigns.target_area
      submit_order(socket, account, source, target, amount)
      {:noreply, socket |> remember_assign(source, target, amount) |> clear_selection()}
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

  # Tap-to-place from the map (`.MapViewport`): a tap on an own territory while
  # reinforcements are unplaced queues one there, a hold queues five
  # (`Hud.placement/4` decides). Each placement is remembered so the dock's
  # Undo can take back the latest one, and the local view is adjusted straight
  # away so the HUD responds before the server's `:reload` replaces it.
  def handle_event(
        "quick_assign",
        %{"area" => area_str} = params,
        %{assigns: %{status: :playing, view: %{ended: false} = view}} = socket
      ) do
    with {:ok, account} <- require_account(socket),
         {:ok, area} <- parse_int(area_str),
         {:ok, requested} <- parse_placement(Map.get(params, "amount", 1)),
         {:ok, amount} <- Hud.placement(view, my_player(view), area, requested) do
      Games.assign(socket.assigns.game_id, account.id, area, amount)

      {:noreply,
       socket
       |> disarm_end_turn()
       |> update(:assign_history, &[{area, amount} | &1])
       |> assign(:view, Hud.adjust_assigned(view, area, amount))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("quick_assign", _params, socket), do: {:noreply, socket}

  # The placement bar's −1: takes one army back off this territory, the same
  # way Undo takes back a whole placement (`Hud.undo_plan/3`).
  def handle_event(
        "unplace_one",
        %{"area" => area_str},
        %{assigns: %{status: :playing, view: %{ended: false} = view}} = socket
      ) do
    with {:ok, account} <- require_account(socket),
         {:ok, area} <- parse_int(area_str),
         {:ok, plan} <- Hud.undo_plan(view, my_player(view), {area, 1}),
         true <- plan.undone > 0 do
      apply_undo(socket, account, plan)
      {:noreply, assign(socket, :view, Hud.adjust_assigned(view, plan.area, -plan.undone))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("unplace_one", _params, socket), do: {:noreply, socket}

  # A phone tap on the map (`.MapViewport`): selects one of your territories
  # (the placement bar opens on it) or targets an enemy neighbour of the
  # selected one, as `Hud.tap_plan/3` decides — a tap never places armies by
  # itself. From `lg` up, and from the keyboard, `select_area` keeps the
  # classic click-a-source, click-a-target flow.
  def handle_event(
        "tap_area",
        %{"area" => area_str},
        %{assigns: %{status: :playing, view: %{ended: false} = view}} = socket
      ) do
    selected = socket.assigns.selected_area

    with {:ok, number} <- parse_int(area_str) do
      case Hud.tap_plan(view, selected, number) do
        {:select, ^selected} ->
          {:noreply, socket}

        {:select, number} ->
          {:noreply,
           assign(socket,
             selected_area: number,
             target_area: nil,
             order_amount: to_string(Hud.gesture_pool(view, my_player(view)) || 0)
           )}

        {:target, number} ->
          source = find_area(view, socket.assigns.selected_area)

          amount =
            if order_queued_to?(source, number),
              do: source.order.amount,
              else: Hud.spare_armies(source)

          {:noreply, assign(socket, target_area: number, order_amount: to_string(amount))}

        :clear ->
          {:noreply, clear_selection(socket)}

        :none ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("tap_area", _params, socket), do: {:noreply, socket}

  # Takes back the latest placement, as `Hud.undo_plan/3` lays out.
  def handle_event(
        "undo_assign",
        _params,
        %{
          assigns: %{
            status: :playing,
            view: %{ended: false} = view,
            assign_history: [latest | rest]
          }
        } = socket
      ) do
    socket = assign(socket, :assign_history, rest)

    with {:ok, account} <- require_account(socket),
         {:ok, plan} <- Hud.undo_plan(view, my_player(view), latest) do
      apply_undo(socket, account, plan)

      {:noreply, assign(socket, :view, Hud.adjust_assigned(view, plan.area, -plan.undone))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("undo_assign", _params, socket), do: {:noreply, socket}

  # Drag-to-order from the map (`.MapViewport`): releasing a drag from an own
  # territory's army token over a neighbour opens the order panel on that
  # pair, having queued, reopened or only drafted the order as
  # `Hud.drag_plan/4` decides.
  def handle_event(
        "drag_order",
        %{"from" => from_str, "to" => to_str},
        %{assigns: %{status: :playing, view: %{ended: false} = view}} = socket
      ) do
    with {:ok, account} <- require_account(socket),
         {:ok, from} <- parse_int(from_str),
         {:ok, to} <- parse_int(to_str),
         plan when plan != :error <- Hud.drag_plan(view, my_player(view), from, to) do
      socket = assign(socket, selected_area: from, target_area: to)

      case plan do
        {:queue, order} ->
          submit_order(socket, account, from, to, order.amount)

          {:noreply,
           assign(socket,
             order_amount: to_string(order.amount),
             view: Hud.put_order(view, from, order)
           )}

        {_reopen_or_draft, amount} ->
          {:noreply, assign(socket, :order_amount, to_string(amount))}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("drag_order", _params, socket), do: {:noreply, socket}

  # The engine has no "cancel order": an order cut to zero armies does
  # nothing when the turn resolves, and the board draws no arrow for it.
  # Only ever removes the order the panel is actually showing — the one
  # queued from the selected area to the selected target.
  def handle_event("remove_order", _params, %{assigns: %{status: :playing}} = socket) do
    %{view: view, selected_area: source, target_area: target} = socket.assigns

    with {:ok, account} <- require_account(socket),
         %{} = area <- source && find_area(view, source),
         true <- order_queued_to?(area, target) do
      submit_order(socket, account, source, target, 0)
      {:noreply, clear_selection(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_order", _params, socket), do: {:noreply, socket}

  # The amount field, stepper and Max only ever rewrite the draft `order_amount`;
  # nothing reaches the game server until `submit_order`, which validates as before.
  # `change_amount` keeps the draft in step with what was typed, so a step or Max
  # after typing starts from the typed number rather than the prefill.
  def handle_event("change_amount", %{"_target" => ["amount_range"]} = params, socket),
    do: {:noreply, assign(socket, :order_amount, Map.get(params, "amount_range", ""))}

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

  # The phone HUD's one-button lens control steps through the same three.
  def handle_event("cycle_lens", _params, socket),
    do: {:noreply, update(socket, :lens, &Hud.next_lens/1)}

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

  defp max_order_amount(%{status: :playing, selected_area: selected} = assigns)
       when not is_nil(selected),
       do: order_limit(assigns.view, selected, assigns.target_area)

  defp max_order_amount(_assigns), do: nil

  # Assign mode tops out at the viewer's unassigned pool; transfer and attack
  # at what the source can actually send — the engine always leaves one army
  # behind, so Max and a full slider never promise more than will go.
  defp order_limit(view, selected, target) do
    case {find_area(view, selected), target, my_player(view)} do
      {nil, _target, _me} -> nil
      {_source, nil, nil} -> nil
      {_source, nil, me} -> me.unassigned_armies
      {source, _target, _me} -> Hud.spare_armies(source)
    end
  end

  # True when `area` has a live order queued to exactly `target`.
  defp order_queued_to?(area, target),
    do: WorldMap.queued_order?(area) and area.order.target == target and not is_nil(target)

  defp find_area(view, number), do: Enum.find(view.areas, &(&1.number == number))

  defp parse_amount(amount_str) do
    case Integer.parse(String.trim(to_string(amount_str))) do
      {amount, _} when amount >= 0 -> amount
      _ -> -1
    end
  end

  defp clear_selection(socket),
    do: assign(socket, selected_area: nil, target_area: nil, order_amount: "")

  defp disarm_end_turn(socket) do
    if timer = socket.assigns.end_turn_timer, do: Process.cancel_timer(timer)
    assign(socket, end_turn_armed: false, end_turn_timer: nil)
  end

  # An Assign from the order panel joins the Undo history like a tap does
  # (`Hud.reconcile_history/2` trims it to what the server really queued).
  defp remember_assign(socket, source, nil, amount) when amount > 0,
    do: update(socket, :assign_history, &[{source, amount} | &1])

  defp remember_assign(socket, _source, _target, _amount), do: socket

  # Carries out a `Hud.undo_plan/3`: the engine can only clear an area's whole
  # assignment, so clear it, re-queue what stays, and put back the area's
  # order at what it can still send.
  defp apply_undo(socket, account, plan) do
    game_id = socket.assigns.game_id
    Games.unassign(game_id, account.id, plan.area)
    if plan.keep > 0, do: Games.assign(game_id, account.id, plan.area, plan.keep)

    with {target, amount} <- plan.order,
         do: submit_order(socket, account, plan.area, target, amount)
  end

  defp parse_placement("all"), do: {:ok, :all}
  defp parse_placement(value), do: parse_int(value)

  defp parse_int(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp require_account(socket) do
    case socket.assigns.current_account do
      nil -> :error
      account -> {:ok, account}
    end
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

  # Computed once per render (not per sub-template) so `status_line/1`'s replay
  # controls and `board/1`'s WorldMap + results list always agree on the same
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
  # (`status_line/1`'s ended announcement) and the `:board` slot (`game_over/1`) — `find_winner/1`
  # and `my_player/1` each used to run twice per render (once per slot, again inside `game_over/1`)
  # since both slots render from the same top-level `assigns` but neither could see the other's
  # local computation.
  defp maybe_assign_outcome(%{status: :playing} = assigns) do
    winner = find_winner(assigns.view.players)
    me = my_player(assigns.view)
    role = viewer_role(assigns.view, winner, me)

    assign(assigns,
      winner: winner,
      viewer_role: role,
      headline: headline(role, winner),
      outcome: viewer_outcome(role, me, length(assigns.view.players))
    )
  end

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
            <span id="game-status">{status_line(assigns)}</span>
            <form
              :if={@status == :playing}
              id="lens-form"
              phx-change="set_lens"
              class={[@stage && "hidden lg:block"]}
            >
              <SegmentedControl.segmented_control name="lens" label="Map lens" value={@lens}>
                <:option value="owner">Owner</:option>
                <:option value="region">Region control</:option>
                <:option value="frontier">Frontier</:option>
              </SegmentedControl.segmented_control>
            </form>
            <div class="ml-auto flex items-center gap-[var(--space-2)]">
              <button
                :if={@stage}
                type="button"
                id="lens-cycle"
                phx-click="cycle_lens"
                aria-label={"Map lens: #{Hud.lens_name(@lens)}. Switch lens"}
                class="hud-chip lg:hidden"
              >
                <.icon name={Hud.lens_icon(@lens)} class="size-5" />
              </button>
              <%!-- The roster as avatars doubles as the drawer opener on a phone:
              each seat's colour, initial and a tick once they've ended their
              turn — who you're waiting on, at a glance. --%>
              <button
                type="button"
                id="drawer-open"
                aria-controls="game-drawer"
                aria-expanded="false"
                aria-label="Players and chat"
                phx-mounted={JS.ignore_attributes(["aria-expanded"])}
                class="hud-chip relative rounded-[var(--radius-sm)] px-[var(--space-3)] py-[var(--space-1)] text-sm font-semibold bg-surface-muted hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring lg:hidden"
              >
                <%= if @status == :playing do %>
                  <span class="flex items-center -space-x-1.5" aria-hidden="true">
                    <span
                      :for={p <- @view.players}
                      class={["hud-avatar world-map-owner", p.eliminated && "opacity-40"]}
                      data-owner={WorldMap.owner_slot(p.number)}
                      data-done={p.done && !p.eliminated}
                    >
                      {String.first(p.name)}
                    </span>
                  </span>
                <% else %>
                  Players
                <% end %>
                <span
                  data-unread-dot
                  aria-hidden="true"
                  phx-mounted={JS.ignore_attributes(["class"])}
                  class="hidden absolute -right-1 -top-1 size-2.5 rounded-full bg-danger"
                />
              </button>
              <button
                id="fullscreen-toggle"
                type="button"
                phx-hook=".Fullscreen"
                aria-pressed="false"
                aria-label="Full screen"
                class="hidden shrink-0 items-center justify-center rounded-[var(--radius-sm)] p-[var(--space-2)] border border-border bg-surface hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus-ring"
              >
                <.icon name="hero-arrows-pointing-out" class="fullscreen-toggle-icon size-5" />
              </button>
            </div>
          </:status>

          <:board>
            <%!-- h-full: stage mode's <main> (GameLayout) is the definite-height grid
          row the board's own figure/`.world-map`/<svg> height chain needs
          (board/1's moduledoc) — without it here, this wrapper's own
          auto-by-default height would break that chain one level up. Outside
          stage mode <main> has no definite height either, so this resolves to
          plain `auto` there (CSS percentage-height-of-indefinite-ancestor
          rule) — a no-op. --%>
            <div id="game-board-surface" class="h-full">
              <Layouts.flash_group flash={@flash} />
              <%= case @status do %>
                <% :lobby -> %>
                  {lobby(assigns)}
                <% :playing -> %>
                  {board(assigns)}
              <% end %>
            </div>
          </:board>

          <%!-- Seated players only: a spectator has no orders to compose and no
        turn to end, so an always-present slot would render an empty,
        bordered "Actions" sheet for them. --%>
          <:dock :if={@stage && @view.viewer_number}>
            {dock(assigns)}
          </:dock>

          <:players>
            <.player_list
              players={@view.players}
              viewer_number={@view.viewer_number}
              status={@status}
              ended={@status == :playing and @view.ended}
              map_name={Map.get(@view, :map_name)}
            />
            <%= if @status == :playing do %>
              {players_extras(assigns)}
            <% end %>
            <.chat
              messages={Map.get(@view, :messages, [])}
              chat_form={@chat_form}
              logged_in={!!@current_account}
            />
            <%!-- Below lg only: there Quit lives in the drawer so it can't be hit
          by accident from the dock (docs/mobile-battle-mode.md §2, rule 3).
          :players renders once, inside the one <dialog> GameLayout shows as
          the mobile drawer and the lg: rail alike, so lg:hidden keeps the
          desktop rail unchanged — above lg Quit stays in #turn-controls
          (dock/1), where it has always been ("above lg nothing changes"). --%>
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Fullscreen">
        // iOS Safari has no Fullscreen API for arbitrary elements
        // (`document.fullscreenEnabled` is false there) — the button stays
        // hidden rather than shown-and-broken; those players get the
        // browser-chrome-free experience through the PWA install instead
        // (manifest.webmanifest, root layout metas).
        export default {
          mounted() {
            if (!document.fullscreenEnabled) return
            this.el.classList.remove("hidden")
            this.el.classList.add("inline-flex")
            this.onClick = () => this.toggle()
            this.onFullscreenChange = () => this.syncPressed()
            this.el.addEventListener("click", this.onClick)
            document.addEventListener("fullscreenchange", this.onFullscreenChange)
          },
          toggle() {
            if (document.fullscreenElement) {
              document.exitFullscreen()
            } else {
              document.getElementById("game-board")?.requestFullscreen({ navigationUI: "hide" })
            }
          },
          syncPressed() {
            const pressed = !!document.fullscreenElement
            this.el.setAttribute("aria-pressed", pressed ? "true" : "false")
            this.el.querySelector(".fullscreen-toggle-icon")?.classList.toggle(
              "hero-arrows-pointing-in",
              pressed
            )
            this.el.querySelector(".fullscreen-toggle-icon")?.classList.toggle(
              "hero-arrows-pointing-out",
              !pressed
            )
          },
          destroyed() {
            this.el.removeEventListener("click", this.onClick)
            document.removeEventListener("fullscreenchange", this.onFullscreenChange)
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
      <script :type={Phoenix.LiveView.ColocatedHook} name=".TurnReplay">
        // Replays the last resolved turn from the JSON payload LiveView
        // put in `data-steps` (`GameLive.Replay.steps/4`, already fog-filtered) —
        // every play/step/back afterwards is pure client-side timing, no
        // `pushEvent` round trip ("the hook owns the timing"). Mounted on a
        // wrapper that renders every turn regardless of whether there's anything
        // to replay, so `updated()` reliably fires exactly once per resolved
        // turn (comparing `data-turn`) whether or not the *previous* turn had
        // any visible events of its own.
        //
        // This hook only owns its own buttons and announcement. Where the
        // replay is goes out as a `gc:replay` window event
        // (`{current, animate, counts}`); the board (`WorldMap`'s
        // `.MapReplay`) and the results list (`.TurnResultsList`) each apply
        // it to their own markup and re-apply it after LiveView patches them.
        // `gc:replay-sync` asks for a resend (a listener mounting late).
        //
        // Delegates clicks from the wrapper rather than binding the buttons
        // directly: the buttons themselves come and go (rendered only when
        // `@steps != []`), but this element's `id` never does, so LiveView
        // never remounts the hook — only a plain `updated()` patch.
        export default {
          mounted() {
            this.current = -1
            this.timer = null
            this.seenTurn = this.el.dataset.turn
            this.el.addEventListener("click", (e) => this.onClick(e))
            this.onSync = () => this.broadcast()
            window.addEventListener("gc:replay-sync", this.onSync)
            this.render()
          },

          updated() {
            const turn = this.el.dataset.turn
            const isNewTurn = turn !== this.seenTurn
            this.seenTurn = turn

            if (!isNewTurn) {
              // Some *other* part of this LiveView patched (a chat message, a
              // player's status pill) and happened to touch this subtree —
              // must not wipe a viewer's in-progress replay position.
              this.render()
              return
            }

            this.stop()
            this.current = -1

            if (!this.reducedMotion() && this.steps().length > 0) {
              this.play()
            } else {
              this.render()
            }
          },

          destroyed() {
            this.stop()
            window.removeEventListener("gc:replay-sync", this.onSync)
          },

          onClick(e) {
            if (e.target.closest("[data-replay-play]")) this.play()
            else if (e.target.closest("[data-replay-back]")) { this.stop(); this.show(this.current - 1) }
            else if (e.target.closest("[data-replay-forward]")) { this.stop(); this.show(this.current + 1) }
          },

          steps() {
            return JSON.parse(this.el.dataset.steps)
          },

          reducedMotion() {
            return window.matchMedia("(prefers-reduced-motion: reduce)").matches
          },

          play() {
            this.stop()
            this.show(-1)
            this.timer = setInterval(() => {
              if (this.current >= this.steps().length - 1) { this.stop(); return }
              this.show(this.current + 1)
            }, 900)
          },

          stop() {
            if (this.timer) clearInterval(this.timer)
            this.timer = null
          },

          show(index) {
            const steps = this.steps()
            this.current = Math.max(-1, Math.min(index, steps.length - 1))
            this.render()
          },

          // The running army count of every area touched up to the current
          // step; areas no step has touched yet keep their live count.
          counts(steps) {
            const counts = {}
            for (let i = 0; i <= this.current; i++) {
              (steps[i]?.counts || []).forEach(({area, value}) => { counts[area] = value })
            }
            return counts
          },

          broadcast() {
            const detail = {
              current: this.current,
              animate: !this.reducedMotion(),
              counts: this.counts(this.steps())
            }
            window.dispatchEvent(new CustomEvent("gc:replay", { detail }))
          },

          render() {
            const steps = this.steps()
            this.broadcast()

            const announce = document.getElementById("turn-replay-announce")
            if (announce) announce.textContent = this.current >= 0 ? (steps[this.current]?.text || "") : ""

            const back = this.el.querySelector("[data-replay-back]")
            const forward = this.el.querySelector("[data-replay-forward]")
            if (back) back.disabled = this.current <= -1
            if (forward) forward.disabled = this.current >= steps.length - 1
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".TurnResultsList">
        // Marks the step the replay is on in the accessible results list
        // (`turn_results/1`), from `.TurnReplay`'s `gc:replay` broadcast, and
        // re-applies it after LiveView patches the list (the drawer it sits
        // in re-renders on every chat message).
        export default {
          mounted() {
            this.current = -1
            this.onReplay = (e) => {
              this.current = e.detail.current
              this.apply()
            }
            window.addEventListener("gc:replay", this.onReplay)
            window.dispatchEvent(new CustomEvent("gc:replay-sync"))
          },

          updated() {
            this.apply()
          },

          destroyed() {
            window.removeEventListener("gc:replay", this.onReplay)
          },

          apply() {
            this.el.querySelectorAll("[data-step]").forEach((el) => {
              const isCurrent = Number(el.dataset.step) === this.current
              el.classList.toggle("is-current", isCurrent)
              if (isCurrent) el.setAttribute("aria-current", "step")
              else el.removeAttribute("aria-current")
            })
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
    assigns =
      assign(assigns,
        ended_pill: ended_pill(assigns.view),
        turn_hint: !assigns.view.ended && Hud.turn_hint(assigns.view, my_player(assigns.view)),
        income:
          !assigns.view.ended && Hud.gesture_pool(assigns.view, my_player(assigns.view)) &&
            Hud.income(assigns.view, my_player(assigns.view))
      )

    ~H"""
    <span class="turn-pill">
      <span class="heading-3 tabular-nums">
        Turn {@view.turn}
      </span>
      <%!-- aria-live="off": this changes on every placement, and the strip
      around it is a live region that would otherwise read each one out. --%>
      <span :if={@turn_hint} id="turn-hint" class="turn-hint" aria-live="off">{@turn_hint}</span>
      <%!-- Your army at a glance: everything you have on the board and in hand,
      and what next turn brings (the breakdown is in the Players drawer). --%>
      <span :if={@income} id="army-summary" class="army-summary" aria-live="off">
        {@income.armies} armies · +{@income.total} next turn
      </span>
    </span>
    <StatusPill.status_pill :if={!@view.ended} tone="active" class="hud-desktop-only">
      In progress
    </StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.ended} tone={@ended_pill.tone}>
      {@ended_pill.label}
    </StatusPill.status_pill>
    <StatusPill.status_pill :if={@view.is_fogged} tone="partial">Fog of war</StatusPill.status_pill>
    <Button.button
      type="button"
      intent="neutral"
      id="map-fit"
      phx-hook=".MapFit"
      aria-label="Reset map zoom"
      class="hud-chip"
    >
      <.icon name="hero-globe-americas" class="size-5 lg:hidden" />
      <span class="hidden lg:inline">Fit</span>
    </Button.button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".MapFit">
      // The .MapViewport hook (world_map.ex) lives on a different element,
      // so rather than it reaching out with a document-level click listener,
      // this button announces itself over a window event.
      export default {
        mounted() {
          this.el.addEventListener("click", () => window.dispatchEvent(new CustomEvent("gc:map-fit")))
        }
      }
    </script>
    <.turn_replay_controls turn={@view.turn} steps={@replay_steps} />
    <span :if={@view.ended} id="game-over-announce" class="sr-only">
      {@headline}<span :if={@outcome}>{" " <> @outcome}</span>
    </span>
    """
  end

  # The pill used to be tone "done" (green, terminal-success) for every viewer once a
  # game ended, so a losing player's own status strip told them they'd succeeded. It now reflects
  # the *viewer's* outcome, matching `viewer_outcome/2` below — a spectator gets the neutral
  # "Ended", a seated player gets their own Victory/Defeat.
  defp ended_pill(view) do
    case my_player(view) do
      nil -> %{tone: "new", label: "Ended"}
      %{place: 1} -> %{tone: "done", label: "Victory"}
      _ -> %{tone: "blocked", label: "Defeat"}
    end
  end

  # Play/back/forward for the last-turn replay, plus the live-region
  # announcement span the `.TurnReplay` hook narrates each step into (picked up by
  # `GameLayout`'s already-`aria-live="polite"` `:status` section — see that
  # module's moduledoc). The wrapper itself renders every turn regardless of
  # whether there's anything to replay, and only its *contents* are conditional —
  # `data-turn` has to change on an element the hook stays mounted on the whole
  # time for `updated/0` to reliably tell "a new turn resolved" from "this turn
  # simply had no visible events", including the very next turn that does.
  # Stepping/announcing here is otherwise plain client-side JS (no phx-click):
  # "the hook owns the timing", not the server.
  attr :turn, :integer, required: true
  attr :steps, :list, required: true

  defp turn_replay_controls(assigns) do
    assigns = assign(assigns, :steps_json, Jason.encode!(assigns.steps))

    ~H"""
    <div
      id="turn-replay-controls"
      phx-hook=".TurnReplay"
      data-turn={@turn}
      data-steps={@steps_json}
      class="flex items-center gap-[var(--space-2)]"
    >
      <span :if={@steps != []} class="flex items-center gap-[var(--space-2)]">
        <Button.button id="turn-replay-play" type="button" data-replay-play class="hud-chip">
          <span class="lg:hidden">▶ Replay</span>
          <span class="hidden lg:inline">Turn {@turn} results ▶</span>
        </Button.button>
        <Button.button
          id="turn-replay-back"
          type="button"
          intent="neutral"
          data-replay-back
          class="hud-chip"
          aria-label="Previous step"
        >
          ◀<span class="hidden lg:inline">&nbsp;Step</span>
        </Button.button>
        <Button.button
          id="turn-replay-forward"
          type="button"
          intent="neutral"
          data-replay-forward
          class="hud-chip"
          aria-label="Next step"
        >
          <span class="hidden lg:inline">Step&nbsp;</span>▶
        </Button.button>
      </span>
      <span id="turn-replay-announce" class="sr-only"></span>
    </div>
    """
  end

  defp lobby(assigns) do
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

  # Every map is a responsive SVG (`WorldMap`) — the legacy per-owner GIF
  # sprites `Index.cshtml` composited at fixed pixel offsets are gone. The
  # order panel, turn controls, region bonuses, your orders, turn results and
  # Quit used to sit in a rail column beside the map here; stage mode
  # (`docs/mobile-battle-mode.md` §4.3) moved them into `:dock`/`:players` in
  # `render_game/1` instead, so this is just the map and its accessible table
  # now — `@stage` (true exactly when this isn't the ended state) gives the
  # figure a definite height to fill so the map can fill the stage's board
  # area instead of sizing to its own aspect ratio (`.world-map` in `app.css`
  # completes the height chain down to the `<svg>` below `lg:`).
  defp board(assigns) do
    ~H"""
    <.game_over
      :if={@view.ended}
      view={@view}
      winner={@winner}
      headline={@headline}
      outcome={@outcome}
    />
    <figure class={["m-0 w-full", @stage && "h-full"]}>
      <WorldMap.world_map
        map_name={@view.map_name}
        areas={@view.areas}
        players={@view.players}
        selected_area={@selected_area}
        target_area={@target_area}
        lens={@lens}
        viewer_number={@view.viewer_number}
        interactive={!@view.ended}
        replay_steps={@replay_steps}
        game_id={@game_id}
        unassigned={Hud.gesture_pool(@view, my_player(@view))}
      />
      <figcaption
        :if={@view.ended && @winner}
        id="game-over-caption"
        class="mt-[var(--space-2)] text-[length:var(--text-sm)] text-text-muted"
      >
        {winner_caption(@winner, length(@view.areas))}
      </figcaption>
    </figure>
    <.board_table areas={@view.areas} players={@view.players} />
    """
  end

  # The dock's idle row (End Turn/Waiting/Force Turn) when nothing is
  # selected, or the order panel once a territory is — never both, so a
  # player never has to scroll the sheet to find the button they want
  # (`docs/mobile-battle-mode.md` §4.3, "Dock contents by state"). Only
  # rendered at all while `@stage` is true (`render_game/1`'s `:dock` slot),
  # which already implies `@view.ended == false` — but not that there's a
  # seated player: a spectator's `viewer_number` is `nil`, so `my_player/1`
  # returns `nil` and a turn-controls row built around `my_player(@view).done`
  # must stay gated on `@view.viewer_number`, same as the original
  # (pre-stage) turn-controls div was.
  #
  # The idle row reads like a game HUD: an Undo for the latest placed
  # reinforcement, a coach line saying what to do next, and End Turn as a big
  # thumb button whose ring fills as reinforcements are placed. Ending a turn
  # with armies still unplaced takes a second tap (`arm_end_turn`).
  defp dock(assigns) do
    me = assigns.view.viewer_number && my_player(assigns.view)

    assigns =
      assign(assigns,
        me: me,
        progress: me && Hud.placement_progress(assigns.view, me),
        coach: me && Hud.coach_line(assigns.view, me, :phone),
        desktop_coach: me && Hud.coach_line(assigns.view, me, :desktop)
      )

    ~H"""
    <.order_panel
      :if={@selected_area}
      view={@view}
      selected_area={@selected_area}
      target_area={@target_area}
      order_amount={@order_amount}
    />
    <div :if={!@selected_area && @me} id="turn-controls" class="turn-controls">
      <button
        :if={@assign_history != [] && !@me.done}
        type="button"
        id="undo-assign"
        phx-click="undo_assign"
        aria-label="Undo last placement"
        class="hud-chip turn-controls-undo lg:hidden"
      >
        <.icon name="hero-arrow-uturn-left" class="size-5" />
      </button>
      <p :if={@coach} id="turn-coach" class="turn-coach">
        <span class="lg:hidden">{@coach}</span>
        <span class="hidden lg:inline">{@desktop_coach}</span>
      </p>
      <div class="turn-controls-actions">
        <button
          :if={!@me.done}
          type="button"
          id="end-turn"
          phx-click={
            if(@me.unassigned_armies == 0 or @end_turn_armed, do: "done", else: "arm_end_turn")
          }
          data-unplaced={@me.unassigned_armies}
          class={[
            "end-turn",
            @me.unassigned_armies == 0 && "end-turn--ready",
            @end_turn_armed && "is-armed"
          ]}
        >
          <svg class="end-turn-ring" viewBox="0 0 100 100" aria-hidden="true">
            <circle class="end-turn-ring-track" cx="50" cy="50" r="46" pathLength="100" />
            <circle
              class="end-turn-ring-fill"
              cx="50"
              cy="50"
              r="46"
              pathLength="100"
              stroke-dashoffset={100 - round(@progress * 100)}
            />
          </svg>
          <span class="end-turn-label">
            {if @end_turn_armed,
              do: "#{@me.unassigned_armies} unplaced · tap again",
              else: "End Turn"}
          </span>
        </button>
        <Button.button
          id="force-turn"
          intent="neutral"
          class="turn-controls-force"
          phx-click="force_turn"
        >
          Force Turn
        </Button.button>
        <%!-- Desktop only: below lg the drawer carries Quit instead (the
        #quit-button in render_game/1's :players slot). --%>
        <Button.button
          :if={!@me.eliminated}
          id="turn-controls-quit"
          intent="neutral"
          class="max-lg:hidden"
          phx-click="quit"
        >
          Quit
        </Button.button>
        <span :if={@me.done} class="turn-waiting">Waiting on other players…</span>
      </div>
    </div>
    """
  end

  # Region bonuses, your queued orders and the last turn's results, in the
  # `:players` rail between the roster and chat (`docs/mobile-battle-mode.md`
  # §4.3) — only ever called while `@status == :playing` (`render_game/1`).
  defp players_extras(assigns) do
    me = assigns.view.viewer_number && my_player(assigns.view)

    assigns =
      assign(assigns,
        my_orders: my_orders(assigns.view),
        income: me && !me.eliminated && Hud.income(assigns.view, me),
        unplaced: me && me.unassigned_armies
      )

    ~H"""
    <.income_card :if={!@view.ended && @income} income={@income} unplaced={@unplaced} />
    <.region_bonuses :if={!@view.ended} map_name={@view.map_name} />
    <.your_orders_card :if={@my_orders != []} orders={@my_orders} />
    <.turn_results :if={@replay_steps != []} turn={@view.turn} steps={@replay_steps} />
    """
  end

  # `engine.ended` is an explicit state instead of a live turn stuck on "Waiting on
  # other players… [Force Turn]" with the outcome buried as a small "place 1" in the roster.
  # That state carries the weight the finale of the game deserves: a headline the size of
  # a real heading (not `text-lg`), the board's own owner colour bleeding into the panel instead
  # of a neutral `border-divider` box, full per-player final stats (not just a placing number —
  # `player_list`'s roster hides armies/areas the instant `place > 0`, which is every seated
  # player once the game has ended, winner included), and a primary next action (`Play again`)
  # instead of leaving Send in chat as the only `intent="primary"` button on the page.
  #
  # `role="status"`/`aria-live="polite"` never fired here — this section exists at first render
  # for anyone loading an already-finished game, and a live region only announces *changes*
  # after mount. `aria-labelledby` gives it a name for landmark navigation without pretending to
  # announce a mutation that already happened by the time the socket connects; `status_line/1`'s
  # `#game-over-announce` (inside `GameLayout`'s already-`aria-live="polite"` status strip) covers
  # the live-flip case for a player connected when the game ends.
  attr :view, :map, required: true
  attr :winner, :map, required: true
  attr :headline, :string, required: true
  attr :outcome, :string, default: nil

  defp game_over(assigns) do
    standings = assigns.view.players |> Enum.filter(&(&1.place > 0)) |> Enum.sort_by(& &1.place)
    assigns = assign(assigns, :standings, standings)

    ~H"""
    <section
      id="game-over"
      aria-labelledby="game-over-heading"
      class="world-map-owner mb-[var(--space-4)] flex flex-col gap-[var(--space-3)] rounded-[var(--radius-md)] border border-divider border-l-4 border-l-[color:var(--map-owner-fill,var(--map-owner-0))] bg-surface p-[var(--space-5)]"
      data-owner={@winner && WorldMap.owner_slot(@winner.number)}
    >
      <Kicker.kicker>Game Over · Turn {@view.turn}</Kicker.kicker>

      <h2
        id="game-over-heading"
        class="m-0 font-heading font-[var(--font-heading-weight)] text-[length:var(--heading-2)] leading-[var(--heading-leading)] tracking-[var(--heading-tracking)] text-text"
      >
        {@headline}
      </h2>

      <p :if={@outcome} id="game-over-outcome" class="m-0 text-text">{@outcome}</p>

      <ol
        :if={@standings != []}
        id="game-over-standings"
        class="mt-[var(--space-2)] flex flex-col gap-[var(--space-2)]"
      >
        <li
          :for={p <- @standings}
          class="flex items-center justify-between gap-[var(--space-4)] text-[length:var(--text-sm)]"
        >
          <span class="flex items-center gap-[var(--space-2)]">
            <span
              class="world-map-swatch world-map-owner"
              data-owner={WorldMap.owner_slot(p.number)}
              aria-hidden="true"
            />
            <span class={p.place == 1 && "font-semibold"}>{p.place}. {p.name}</span>
          </span>
          <span :if={p.place == 1} class="text-text-muted">
            {p.armies} armies · {p.areas} territories
          </span>
        </li>
      </ol>

      <div class="mt-[var(--space-2)] flex flex-wrap gap-[var(--space-3)]">
        <Button.button id="game-over-play-again" intent="primary" navigate={~p"/Create-Game"}>
          Play again
        </Button.button>
        <Button.button id="game-over-home" intent="neutral" navigate={~p"/"}>
          Back to Home
        </Button.button>
      </div>
    </section>
    """
  end

  defp find_winner(players), do: Enum.find(players, &(&1.place == 1))

  # A game can also end by every other seat quitting/being eliminated one at a time
  # (`Engine.eliminate_player/2` zeroes `areas`/`armies` on elimination) rather than the winner
  # capturing the whole board, so the winner's own `areas` can be less than the board's total —
  # "all" is only accurate when the two happen to match.
  defp winner_caption(winner, total_areas) when winner.areas == total_areas,
    do: "#{winner.name} holds all #{total_areas} territories."

  defp winner_caption(winner, total_areas),
    do: "#{winner.name} holds #{winner.areas} of #{total_areas} territories."

  # :winner/:loser require a seat (`my_player/1`); anyone else — logged out, or logged in but
  # never joined this game — is a :spectator, same viewer this module already treats as one
  # everywhere else (`viewer_number: nil`).
  defp viewer_role(view, winner, me) do
    cond do
      winner && winner.number == view.viewer_number -> :winner
      me -> :loser
      true -> :spectator
    end
  end

  defp headline(:winner, _winner), do: "Victory"
  defp headline(:loser, _winner), do: "Defeat"
  defp headline(:spectator, nil), do: "Game Over"
  defp headline(:spectator, winner), do: "#{winner.name} wins"

  # The viewer's own line under the headline; `nil` for a spectator.
  defp viewer_outcome(:winner, _me, _total), do: "You won."
  defp viewer_outcome(:loser, me, total), do: "You placed #{ordinal(me.place)} of #{total}."
  defp viewer_outcome(:spectator, _me, _total), do: nil

  defp my_player(view), do: Enum.find(view.players, &(&1.number == view.viewer_number))

  # Player-facing ordinal ("1st place"), replacing the engine's bare `place` integer
  # ("place 1") that used to leak straight into the UI — port of `Player.cs`'s `GetPlace()`.
  defp ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"

  defp ordinal(n) do
    case rem(n, 10) do
      1 -> "#{n}st"
      2 -> "#{n}nd"
      3 -> "#{n}rd"
      _ -> "#{n}th"
    end
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

  # A slider and quick picks (1 · Half · Max) sit beside the exact number, so a
  # thumb can set an amount without the keyboard. Opened on an order that is
  # already queued (a drag, or tapping its arrow) it edits that order: the
  # primary button updates it and Remove takes it off the board. A territory
  # carries one order a turn, so when a different one is already queued from
  # the source the panel says which order submitting would replace.
  #
  # With a target picked the card carries `data-anchor`, the board point at
  # the middle of the order's arrow; on a phone `.MapViewport` floats the card
  # beside that point instead of leaving it in the dock.
  defp order_panel(assigns) do
    view = assigns.view
    source = find_area(view, assigns.selected_area)
    target = assigns.target_area && find_area(view, assigns.target_area)
    mode = order_mode(view, target)
    limit = order_limit(view, assigns.selected_area, assigns.target_area) || 0
    queued? = WorldMap.queued_order?(source)
    editing? = order_queued_to?(source, assigns.target_area)

    replaces =
      if mode != :assign and queued? and not editing?,
        do: find_area(view, source.order.target)

    assigns =
      assign(assigns,
        source: source,
        target: target,
        mode: mode,
        limit: limit,
        half: max(div(limit, 2), 1),
        amount: max(parse_amount(assigns.order_amount), 0),
        editing: editing?,
        replaces: replaces,
        anchor: target && WorldMap.order_anchor(view.map_name, source.number, target.number)
      )

    ~H"""
    <Card.card
      id="order-panel"
      class={["order-panel min-w-[16rem]", "order-panel--#{@mode}"]}
      data-anchor={@anchor}
    >
      <:header>
        <%= if @mode == :assign && @source do %>
          <span class="lg:hidden">Place armies on {@source.name}</span>
          <span class="hidden lg:inline">{order_panel_title(@mode, @target)}</span>
        <% else %>
          {order_panel_title(@mode, @target)}
        <% end %>
      </:header>
      <%!-- The phone's placement bar: a tap selected this territory; these
      buttons place on it, one tap each, and −1 takes one back. Below `lg`
      it replaces the amount form for placing (the form stays for orders). --%>
      <div :if={@mode == :assign && @source} id="placement-bar" class="placement-bar lg:hidden">
        <p id="placement-status" class="placement-status">
          <b>{@source.armies}</b>
          armies here<span :if={@source.pending_armies > 0}>
            (+{@source.pending_armies} placed)
          </span>
          · <b>{@limit}</b>
          left to place
        </p>
        <div class="placement-buttons">
          <Button.button
            id="place-minus"
            type="button"
            intent="neutral"
            phx-click="unplace_one"
            phx-value-area={@source.number}
            disabled={@source.pending_armies == 0}
            aria-label="Take one army back"
          >
            −1
          </Button.button>
          <Button.button
            id="place-one"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount="1"
            disabled={@limit == 0}
          >
            +1
          </Button.button>
          <Button.button
            id="place-five"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount={Hud.hold_amount()}
            disabled={@limit == 0}
          >
            +{Hud.hold_amount()}
          </Button.button>
          <Button.button
            id="place-all"
            type="button"
            phx-click="quick_assign"
            phx-value-area={@source.number}
            phx-value-amount="all"
            disabled={@limit == 0}
          >
            All {@limit}
          </Button.button>
        </div>
        <p class="placement-hint">
          Tap another of your territories to place there, or drag this one's army token onto a neighbour to attack or move.
        </p>
        <Button.button id="placement-done" type="button" intent="neutral" phx-click="cancel_order">
          Done
        </Button.button>
      </div>
      <form
        id="order-form"
        phx-change="change_amount"
        phx-submit="submit_order"
        class={["flex flex-col gap-[var(--space-3)]", @mode == :assign && "max-lg:hidden"]}
      >
        <p :if={@replaces} id="order-replaces" class="order-replaces">
          Replaces {@source.name}'s order to {@replaces.name}: one order per territory each turn.
        </p>
        <div class="order-amount-row">
          <Input.input
            id="order-amount"
            name="amount"
            type="number"
            min="0"
            label="Armies"
            value={@order_amount}
            inputmode="numeric"
            pattern="[0-9]*"
            autocomplete="off"
            enterkeyhint="done"
            class="order-amount-input"
          />
          <%!-- A plain range input: the design system's Input has no slider
          variant, and its label/field wrapper doesn't fit a bare track. --%>
          <input
            :if={@limit > 0}
            id="order-amount-range"
            name="amount_range"
            type="range"
            min="0"
            max={@limit}
            value={min(@amount, @limit)}
            aria-label="Armies"
            class="order-amount-range"
          />
        </div>
        <div id="order-stepper" class="order-stepper">
          <Button.button
            type="button"
            intent="neutral"
            phx-click="step_amount"
            phx-value-delta="-1"
            aria-label="One army fewer"
          >
            −
          </Button.button>
          <Button.button
            type="button"
            intent="neutral"
            phx-click="step_amount"
            phx-value-delta="1"
            aria-label="One army more"
          >
            +
          </Button.button>
          <Button.button
            :if={@limit > 1}
            id="order-pick-one"
            type="button"
            intent="neutral"
            phx-click="change_amount"
            phx-value-amount="1"
          >
            1
          </Button.button>
          <Button.button
            :if={@limit > 2}
            id="order-pick-half"
            type="button"
            intent="neutral"
            phx-click="change_amount"
            phx-value-amount={@half}
            aria-label={"Half: #{@half}"}
          >
            ½
          </Button.button>
          <Button.button id="order-pick-max" type="button" intent="neutral" phx-click="max_amount">
            Max
          </Button.button>
        </div>
        <div class="order-actions">
          <Button.button id="order-submit" type="submit" intent="primary" class="order-submit">
            {order_submit_label(@mode)} {@amount}
          </Button.button>
          <Button.button
            :if={(@mode == :assign and @source) && @source.pending_armies > 0}
            type="button"
            intent="neutral"
            phx-click="unassign_order"
          >
            Unassign
          </Button.button>
          <Button.button
            :if={@editing}
            type="button"
            intent="neutral"
            id="remove-order"
            phx-click="remove_order"
          >
            Remove
          </Button.button>
          <Button.button id="order-cancel" type="button" intent="neutral" phx-click="cancel_order">
            {if @editing, do: "Keep", else: "Cancel"}
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

  # The same queued transfers/attacks the board draws as arrows, worded as
  # plain text — an "error prevention" review surface for all five queued orders at
  # once without re-clicking every source territory, and the accessible equivalent of
  # the arrows for anyone who can't see the board (an arrow's own `aria-label` covers
  # it in isolation, but this list is what makes "did I queue everything I meant to"
  # answerable in one place). `WorldMap.order_label/3` words each line so this list and
  # an arrow's `aria-label` can never describe the same order differently.
  # `view.areas` already dropped every non-owner's `order` to `nil` (`PlayerView`'s
  # fog-of-war boundary), so this needs no owner check of its own.
  defp my_orders(view) do
    area_names = WorldMap.area_names(view.areas)

    # A removed order is one cut to zero armies (`remove_order`) — not listed.
    for area <- view.areas, WorldMap.queued_order?(area) do
      WorldMap.order_label(area.name, area.order, Map.fetch!(area_names, area.order.target))
    end
  end

  # Where the viewer's armies stand: on the board, still to place this turn,
  # and what next turn brings, worked out the way the engine does it
  # (`Hud.income/2`) so the player can see why — territories, then each region
  # held outright, then the game's minimum if that is what applies.
  attr :income, :map, required: true
  attr :unplaced, :integer, required: true

  defp income_card(assigns) do
    ~H"""
    <Card.card id="income-breakdown" class="min-w-[16rem]">
      <:header>Your armies</:header>
      <dl class="income-list">
        <div>
          <dt>On the board and in hand</dt>
          <dd class="tabular-nums">{@income.armies}</dd>
        </div>
        <div>
          <dt>Left to place this turn</dt>
          <dd class="tabular-nums">{@unplaced}</dd>
        </div>
        <div class="income-total">
          <dt>Next turn</dt>
          <dd class="tabular-nums">+{@income.total}</dd>
        </div>
        <div>
          <dt>{@income.territories} territories ÷ 2</dt>
          <dd class="tabular-nums">+{@income.base}</dd>
        </div>
        <div :for={bonus <- @income.bonuses}>
          <dt>{bonus.name} held</dt>
          <dd class="tabular-nums">+{bonus.bonus}</dd>
        </div>
        <div :if={@income.bonuses == []}>
          <dt>Region bonuses</dt>
          <dd>none held yet</dd>
        </div>
        <div :if={@income.total == @income.minimum and @income.minimum > 0}>
          <dt>Game minimum applies</dt>
          <dd class="tabular-nums">{@income.minimum}</dd>
        </div>
      </dl>
    </Card.card>
    """
  end

  attr :orders, :list, required: true

  defp your_orders_card(assigns) do
    ~H"""
    <Card.card class="min-w-[16rem]">
      <:header>Your orders</:header>
      <ul id="your-orders" class="flex flex-col gap-[var(--space-1)] text-sm">
        <li :for={order <- @orders}>{order}</li>
      </ul>
    </Card.card>
    """
  end

  # The accessible equivalent of the board's replay arrows/counts — every
  # `GameLive.Replay.steps/4` line as ordinary, always-present text next to the
  # board (works with no JS, and is exactly what `prefers-reduced-motion` falls
  # back to). The `.TurnResultsList` hook toggles `aria-current`/`.is-current`
  # on each `<li>` as the sighted replay steps through them (following
  # `.TurnReplay`'s `gc:replay` broadcast); nothing here depends on it.
  attr :turn, :integer, required: true
  attr :steps, :list, required: true

  defp turn_results(assigns) do
    ~H"""
    <Card.card id="turn-results" class="min-w-[16rem]">
      <:header>Turn {@turn} results</:header>
      <ol
        id="turn-results-list"
        phx-hook=".TurnResultsList"
        class="flex flex-col gap-[var(--space-1)] text-sm list-decimal pl-[var(--space-4)]"
      >
        <li :for={step <- @steps} data-step={step.index}>{step.text}</li>
      </ol>
    </Card.card>
    """
  end

  # Player-facing rule info (GIF-103): every region's control bonus, sourced
  # from the same `MapInfo.regions/1` the board's areas/adjacency already
  # come from rather than hardcoded per-map text, so a future map addition
  # doesn't need a matching edit here.
  #
  # The map itself draws these bonuses as a legend in its bottom-left sea
  # (`WorldMap.legend/1`), like a printed board. That legend is SVG art that
  # shrinks with the board, too small to read below `md:`, so there this
  # list stays visible in the players drawer (`players_extras/1`); from `md:`
  # up it is screen-reader only, since the legend is aria-hidden.
  attr :map_name, :atom, required: true

  defp region_bonuses(assigns) do
    # Same highest-bonus-first order as the map's legend.
    regions = assigns.map_name |> MapInfo.regions() |> Enum.sort_by(&elem(&1, 3), :desc)
    assigns = assign(assigns, :regions, regions)

    ~H"""
    <section
      id="region-bonuses"
      aria-labelledby="region-bonuses-heading"
      class="mt-[var(--space-2)] flex flex-wrap items-baseline gap-x-[var(--space-3)] text-xs leading-tight text-text md:sr-only"
    >
      <h2
        id="region-bonuses-heading"
        class="m-0 font-semibold uppercase tracking-wide text-text-muted"
      >
        Region Bonuses
      </h2>
      <ul class="m-0 flex list-none flex-wrap gap-x-[var(--space-3)] p-0">
        <li
          :for={{_number, name, _num_areas, army_bonus} <- @regions}
          class="flex items-center gap-[var(--space-1)]"
        >
          <span>{name}</span>
          <span class="font-semibold tabular-nums">{army_bonus}</span>
        </li>
      </ul>
    </section>
    """
  end

  # White text alone doesn't meet WCAG 1.4.3 against every owner-slot
  # background — Player.GetColor()'s #FFE45F (owner 3) measures 1.27:1 and
  # #D45D00 (owner 4) measures 3.91:1 against white, both below the 4.5:1
  # (normal) / 3:1 (large) thresholds. The black outline above guarantees
  # legibility independent of tile color, including future map/color
  # additions (GIF-83).
  # Non-visual equivalent of the pixel-positioned board (GIF-81, WCAG 1.3.1): the
  # `<div>` above conveys territory/owner/army-count/adjacency purely through
  # image position and color, which is meaningless to a screen reader in DOM
  # order. This `sr-only` table (same pattern as BarChart/LineChart's fallback
  # table) carries the identical, already fog-of-war-filtered `@view.areas` data
  # as an ordered, navigable structure instead — visually hidden, never
  # `aria-hidden`, so assistive tech can still read it.
  #
  # Owner text goes through `WorldMap.owner_text/2` (GIF-121) — the same function
  # that words the vector board's territory labels — so a fog-hidden area reports
  # "hidden by fog of war" instead of "unclaimed" here exactly as it does there,
  # and the two can never drift apart. A screen reader user still gets exactly
  # what a sighted player sees, no more and no less.
  # Adjacency, unlike owner/armies, is static map topology every viewer already
  # sees rendered on the board regardless of fog, so it's listed in full.
  # The wrapping div, not the table, carries `sr-only`: a table's
  # auto layout algorithm ignores an explicit width smaller than its content's
  # min-content width, so `sr-only` directly on `<table>` still laid it out at
  # its full intrinsic width (measured 824px) and that box pushed the
  # document's scrollWidth even though it was visually hidden. A plain `div`
  # honors the explicit 1px width, and Tailwind's `sr-only` utility already
  # sets `overflow: hidden` (no separate class needed) to clip the oversized
  # table inside it, so nothing here contributes to page scroll. Verified with
  # this fix in place, via a real Chromium session (Playwright) against `mix
  # phx.server`, logged in and viewing both an active and a finished game:
  # `document.documentElement.scrollWidth == clientWidth` holds at 375px and
  # 768px (see game_live_test.exs for the DOM-shape assertion this backs).
  attr :areas, :list, required: true
  attr :players, :list, required: true

  defp board_table(assigns) do
    assigns =
      assigns
      |> assign(:area_names, Map.new(assigns.areas, &{&1.number, &1.name}))
      |> assign(:owner_names, WorldMap.owner_names(assigns.players))

    ~H"""
    <div class="sr-only">
      <table>
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
            <td>{WorldMap.owner_text(area, @owner_names)}</td>
            <td>{area.armies || "—"}</td>
            <td>{adjacent_names(area, @area_names)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp adjacent_names(area, area_names) do
    area.adjacent
    |> Enum.map(&Map.fetch!(area_names, &1))
    |> Enum.join(", ")
  end

  attr :players, :list, required: true
  attr :viewer_number, :any, required: true
  attr :status, :atom, required: true

  attr :ended, :boolean,
    default: false,
    doc: "swaps the Thinking/Done roster for final standings once the game has ended"

  attr :map_name, :atom,
    default: nil,
    doc: "the game's map, once known — in play each player's board colour gets a legend dot"

  # Once the game has ended the roster is the final standings, so it reads in
  # finishing order (legacy `_PlayerList.cshtml` sorts by `Place`) — seat
  # order otherwise. An eliminated player's totals are always "0 (0)" (the
  # engine zeroes them), never informative, so they are left off.
  defp player_list(assigns) do
    assigns = assign(assigns, :players, roster_order(assigns.players, assigns.ended))

    ~H"""
    <ul id="player-list" aria-live="polite" class="flex flex-col gap-[var(--space-2)]">
      <li :for={p <- @players} class="flex items-center justify-between gap-[var(--space-2)]">
        <span class="flex items-center gap-[var(--space-2)]">
          <span
            :if={@map_name}
            class="world-map-swatch world-map-owner"
            data-owner={WorldMap.owner_slot(p.number)}
            aria-hidden="true"
          />
          <span class={p.number == @viewer_number && "font-semibold"}>{p.name}</span>
        </span>
        <span :if={@ended} class="flex items-center gap-[var(--space-2)]">
          <span :if={p.place == 1} aria-hidden="true">🏆</span>
          <span class="text-text-muted">{ordinal(p.place)}</span>
          <span :if={has_totals?(p)} class="text-text-muted">{p.armies} ({p.areas})</span>
          <span class="text-text-muted">Score {p.score}</span>
        </span>
        <span :if={!@ended} class="flex items-center gap-[var(--space-2)]">
          <span :if={!p.eliminated && p.armies} class="text-text-muted">
            {p.armies} ({p.areas})
          </span>
          <span :if={p.eliminated} class="text-text-muted">{ordinal(p.place)}</span>
          <StatusPill.status_pill :if={!p.eliminated} tone={if p.done, do: "done", else: "waiting"}>
            {if p.done, do: "Done", else: "Thinking"}
          </StatusPill.status_pill>
          <Button.button
            :if={@status == :lobby and @viewer_number == 1 and p.number != @viewer_number}
            intent="neutral"
            phx-click="kick"
            phx-value-player_number={p.number}
          >
            Kick
          </Button.button>
        </span>
      </li>
    </ul>
    """
  end

  # Unplaced seats (place 0) sort last, after every finisher.
  defp roster_order(players, true), do: Enum.sort_by(players, &{&1.place == 0, &1.place})
  defp roster_order(players, false), do: players

  defp has_totals?(player), do: (player.armies || 0) > 0 or (player.areas || 0) > 0

  attr :messages, :list, required: true
  attr :chat_form, Phoenix.HTML.Form, required: true
  attr :logged_in, :boolean, required: true

  defp chat(assigns) do
    ~H"""
    <div class="mt-[var(--space-4)] flex flex-col gap-[var(--space-2)]">
      <.form
        :if={@logged_in}
        for={@chat_form}
        id="chat-form"
        phx-submit="send_chat"
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
