defmodule GlobalCombat.Repo do
  use Ecto.Repo,
    otp_app: :global_combat,
    adapter: Ecto.Adapters.MyXQL
end
