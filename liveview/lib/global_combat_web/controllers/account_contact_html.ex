defmodule GlobalCombatWeb.AccountContactHTML do
  use GlobalCombatWeb, :html

  import GlobalCombatWeb.Components.SiteChrome, only: [site_chrome: 1]

  embed_templates "account_contact_html/*"
end
