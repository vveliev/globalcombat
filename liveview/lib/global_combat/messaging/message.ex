defmodule GlobalCombat.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  # `to_id`/`from_id` are deliberately plain integers, not `belongs_to` FKs — see the
  # migration's comment (docs/schema-map.md §3.7): negative `to_id` is the legacy
  # game-forum-broadcast sentinel (`-game.Id`), which a real FK would reject.
  schema "message" do
    field :to_id, :integer
    field :from_id, :integer
    field :sent_at, :utc_datetime
    field :text, :string
    field :read, :boolean, default: false
    field :deleted, :boolean, default: false
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:to_id, :from_id, :sent_at, :text])
    |> validate_required([:to_id, :from_id, :sent_at, :text])
  end
end
