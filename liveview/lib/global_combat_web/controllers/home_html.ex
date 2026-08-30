defmodule GlobalCombatWeb.HomeHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]
  alias GlobalCombat.Accounts.Account

  alias GlobalCombatWeb.Components.Boutique.{
    Badge,
    Button,
    Card,
    LineChart,
    StatCard,
    StatusPill,
    Table
  }

  embed_templates "home_html/*"

  @doc """
  Ports `Utility.PrintTimeSpan` (`GlobalCombat.Core/Utility.cs:39-56`) — used throughout
  Index/PlayerInfo for "Signed Up"/"Last Login" ages. Always rendered `... ago` here (the
  legacy `isInPast` flag defaults `true`; the one `isInPast: false` call site, a turn
  countdown, belongs to the game board, not this surface).
  """
  def timespan_ago(nil), do: "never"

  def timespan_ago(%DateTime{} = since) do
    seconds = DateTime.diff(DateTime.utc_now(), since, :second) |> max(0)
    days = div(seconds, 86_400)

    cond do
      days > 365 -> "#{div(days, 365)} yrs, #{rem(days, 365)} days ago"
      days >= 1 -> "#{days} days, #{rem(div(seconds, 3600), 24)} hrs ago"
      div(seconds, 3600) >= 1 -> "#{div(seconds, 3600)} hrs, #{rem(div(seconds, 60), 60)} min ago"
      div(seconds, 60) >= 1 -> "#{div(seconds, 60)} min, #{rem(seconds, 60)} sec ago"
      true -> "#{seconds} sec ago"
    end
  end

  @doc "Ports `ViewHelpers.AccountLink` (`Web/BaseViews.cs:10-38`) — name link plus an online/offline chat affordance."
  attr :id, :integer, required: true
  attr :name, :string, required: true
  attr :online?, :boolean, default: false
  attr :viewer_id, :integer, default: nil

  def account_link(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-[var(--space-1)]">
      <a href={~p"/Player-Info-#{@id}"} class="hover:underline">{@name}</a>
      <button
        :if={@viewer_id && @viewer_id != @id}
        type="button"
        class="chat-open-btn cursor-pointer"
        data-account-id={@id}
        data-account-name={@name}
        title={
          if @online?,
            do: "Click to chat with #{@name}.",
            else: "#{@name} is offline. Click to message."
        }
      >
        <Badge.badge intent={if @online?, do: "success", else: "neutral"} dot>
          {if @online?, do: "online", else: "offline"}
        </Badge.badge>
      </button>
    </span>
    """
  end

  @doc "Ports `Game.cs`'s `DisplayGameStatus` (`GlobalCombat.Core/Game.cs:783-862`) minus the per-player pip icons and `TimeLeft` — see `GlobalCombat.Games.GameSummary`'s moduledoc for why."
  attr :game, :map, required: true

  def game_row(assigns) do
    ~H"""
    <div class="flex items-center gap-[var(--space-3)] py-[var(--space-2)] border-b border-divider last:border-b-0">
      <a href={~p"/Game-#{@game.id}/"} class="font-semibold hover:underline">{@game.name}</a>
      <.game_status_pill game={@game} />
      <span :if={@game.status == :running} class="text-text-muted text-sm">Turn {@game.turn}</span>
      <span :if={@game.status == :open} class="text-text-muted text-sm">
        {@game.current_players}/{@game.max_players} players
      </span>
      <Badge.badge :if={@game.is_private} intent="neutral">private</Badge.badge>
      <Badge.badge :if={@game.is_fogged} intent="neutral">fogged</Badge.badge>
    </div>
    """
  end

  attr :game, :map, required: true

  defp game_status_pill(assigns) do
    ~H"""
    <StatusPill.status_pill tone={status_tone(@game.status)}>
      {status_label(@game.status)}
    </StatusPill.status_pill>
    """
  end

  defp status_tone(:open), do: "new"
  defp status_tone(:running), do: "active"
  defp status_tone(:finished), do: "done"

  defp status_label(:open), do: "Open"
  defp status_label(:running), do: "Running"
  defp status_label(:finished), do: "Finished"

  @doc "Ports `Account.Rank` — see `GlobalCombat.Accounts.Account.rank/1`."
  def rank(%Account{} = account), do: Account.rank(account)

  @doc """
  Ports `Message.Print`'s `Text.Replace(\"\\n\", \"<br />\")` (`Web/Models/Message.cs:60`) —
  modern `phoenix_html` (v4+) dropped `Phoenix.HTML.Format.text_to_html/2`, so this escapes
  each line explicitly and re-joins with safe `<br/>` markers rather than the paragraph-wrapping
  the removed helper used to do (which would have been a bigger visual change than intended).
  """
  def message_body(text) do
    text
    |> String.split("\n")
    |> Enum.map(&Phoenix.HTML.html_escape/1)
    |> Enum.intersperse({:safe, "<br/>"})
  end
end
