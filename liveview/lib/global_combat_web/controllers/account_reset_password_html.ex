defmodule GlobalCombatWeb.AccountResetPasswordHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.AuthCard, only: [auth_card: 1]
  import GlobalCombatWeb.Components.InlineMessage, only: [inline_message: 1]
  alias GlobalCombatWeb.Components.Boutique.{Button, Input}

  embed_templates "account_reset_password_html/*"
end
