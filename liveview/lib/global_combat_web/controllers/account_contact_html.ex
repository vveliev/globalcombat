defmodule GlobalCombatWeb.AccountContactHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]
  import GlobalCombatWeb.Components.InlineMessage, only: [inline_message: 1]
  alias GlobalCombatWeb.Components.Boutique.{Button, Card, Input, Kicker}

  embed_templates "account_contact_html/*"
end
