defmodule GlobalCombat.Tourneys.Tourney do
  @moduledoc "Port of `Web/Models/Tourney.cs`'s persisted fields (docs/schema-map.md §3.11)."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses [new: "New", running: "Running", finished: "Finished"]

  schema "tourney" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: @statuses, default: :new

    field :max_players, :integer, default: 0
    field :create_time, :utc_datetime
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime

    field :game_size, :integer, default: 2
    field :winners, :integer, default: 1
    field :double_elimination, :boolean, default: false

    field :auto_start, :boolean, default: true
    field :recurring, :boolean, default: false
    field :option_game_id, :integer, default: 700_460

    has_many :tourney_games, GlobalCombat.Tourneys.TourneyGame
    has_many :tourney_players, GlobalCombat.Tourneys.TourneyPlayer
  end

  @doc "`Tourney.InitialGames` -- `MaxPlayers / GameSize`, `0` if `game_size` is `0`."
  def initial_games(%__MODULE__{game_size: 0}), do: 0

  def initial_games(%__MODULE__{max_players: max_players, game_size: game_size}),
    do: div(max_players, game_size)

  @doc "`Tourney.Losers` -- `GameSize - Winners`."
  def losers(%__MODULE__{game_size: game_size, winners: winners}), do: game_size - winners

  @doc "`Tourney.IsStarted` -- `Status != \"New\"`."
  def started?(%__MODULE__{status: status}), do: status != :new

  @doc """
  Port of `Tourney.CreateTournament`'s validation (the DB insert lives in
  `GlobalCombat.Tourneys.create_tourney/1`). `attrs` is expected to supply `initial_games`
  (converted to `max_players` here) rather than `max_players` directly, matching the C#
  model's `InitialGames` setter (`Tourney.cs:47-49`) that the `Create.cshtml` form posts to.
  """
  def create_changeset(tourney, attrs) do
    tourney
    |> cast(attrs, [
      :name,
      :description,
      :game_size,
      :winners,
      :double_elimination,
      :auto_start,
      :recurring,
      :option_game_id
    ])
    |> cast_initial_games(attrs)
    |> validate_required([:name, :game_size, :winners, :max_players])
    |> validate_number(:winners, greater_than: 0)
    |> validate_shape()
    |> put_change(:status, :new)
    |> put_change(:create_time, DateTime.utc_now(:second))
  end

  defp cast_initial_games(changeset, attrs) do
    case Map.get(attrs, "initial_games") || Map.get(attrs, :initial_games) do
      nil ->
        changeset

      initial_games when is_binary(initial_games) ->
        put_change(
          changeset,
          :max_players,
          to_int(initial_games) * get_field(changeset, :game_size)
        )

      initial_games ->
        put_change(changeset, :max_players, initial_games * get_field(changeset, :game_size))
    end
  end

  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  @power_of_two [2, 4, 8, 16, 32, 64, 128, 256]

  defp validate_shape(changeset) do
    game_size = get_field(changeset, :game_size)
    winners = get_field(changeset, :winners)
    max_players = get_field(changeset, :max_players)
    double_elimination? = get_field(changeset, :double_elimination)

    initial_games = if game_size in [nil, 0], do: 0, else: div(max_players || 0, game_size)

    cond do
      initial_games < 2 ->
        add_error(changeset, :initial_games, "At least two initial games required")

      initial_games > 8 and double_elimination? ->
        add_error(
          changeset,
          :double_elimination,
          "A max of 8 initial games with double elimination."
        )

      initial_games not in @power_of_two ->
        add_error(changeset, :initial_games, "Initial games must be a power of two.")

      winners && game_size && winners >= game_size ->
        add_error(changeset, :winners, "Winners must be less than initial game size.")

      true ->
        changeset
    end
  end
end
