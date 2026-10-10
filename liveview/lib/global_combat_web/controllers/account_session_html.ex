defmodule GlobalCombatWeb.AccountSessionHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.AuthCard, only: [auth_card: 1]
  alias GlobalCombatWeb.Components.Boutique.{Button, Input}

  embed_templates "account_session_html/*"
end
