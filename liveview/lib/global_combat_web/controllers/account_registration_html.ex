defmodule GlobalCombatWeb.AccountRegistrationHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.AuthCard, only: [auth_card: 1]
  alias GlobalCombatWeb.Components.Boutique.{Button, Input}

  embed_templates "account_registration_html/*"
end
