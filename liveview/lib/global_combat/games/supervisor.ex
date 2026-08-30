defmodule GlobalCombat.Games.Supervisor do
  @moduledoc "DynamicSupervisor holding one `GlobalCombat.Games.Server` child per live game."

  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
