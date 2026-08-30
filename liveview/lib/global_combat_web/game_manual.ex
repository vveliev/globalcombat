defmodule GlobalCombatWeb.GameManual do
  @moduledoc """
  The rules document players actually read (GIF-33: "carry the content across verbatim rather
  than paraphrasing it"). `priv/game_manual.html` is `Web/Views/Home/GameManual.cshtml`'s body
  (everything after its Razor `@{ ViewBag.Title = ... }` header) extracted byte-for-byte with
  `sed -n '5,$p'` — not retyped — so there's no transcription risk in the rules text, the damage
  tables, or the worked Elo rating example. It's legacy-era HTML (some `<p>` tags are never
  closed) which HEEx's strict tag-balancing would reject if inlined directly into a template,
  hence loading it as a raw asset and rendering with `raw/1` instead.
  """

  @external_resource Path.join(:code.priv_dir(:global_combat), "game_manual.html")
  @manual_html File.read!(Path.join(:code.priv_dir(:global_combat), "game_manual.html"))

  @doc "The verbatim manual body as safe (pre-escaped) HTML, ready for `raw/1` in a template."
  def html, do: @manual_html
end
