defmodule GlobalCombatWeb.Components.Icon do
  @moduledoc """
  Shim so vendored Mishka Chelekom components can `import
  GlobalCombatWeb.Components.Icon, only: [icon: 1]` — Phoenix 1.8's scaffold
  puts `icon/1` on `CoreComponents` directly rather than a standalone Icon
  module, so this just delegates.
  """
  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :any, default: nil

  def icon(assigns), do: GlobalCombatWeb.CoreComponents.icon(assigns)
end
