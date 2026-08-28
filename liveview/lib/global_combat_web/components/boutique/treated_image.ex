defmodule GlobalCombatWeb.Components.Boutique.TreatedImage do
  @moduledoc """
  Photograph — LiveView mirror of `components/react/TreatedImage`
  (claude-design landing grammar, pure tokens). The treatment (filter,
  blend, overlay, mat frame) is emitted per theme from
  `character.image-treatment` (`tokens/brands.json` → `build/css/
  variables.css`), so this component never branches on brand (C6): under
  a brand with no treatment the `--image-*` vars are inert and the image
  renders plain. Treatments across brands: halftone (broadsheet), plate
  (classical), duotone (industry), grayscale (modernist), lighten/darken
  blend (nocturne), washed (organic).

  The frame border/outline, blend mode, filter, and overlay are all
  brand-supplied custom properties rather than scale steps, so — like
  `PullQuote`'s hang — they stay inline `style` referencing the vars,
  mirroring React's inline `border`/`outline`/`mixBlendMode`/`filter`.
  `shape` maps to a fixed set of radius tokens, which Tailwind's bracket
  syntax expresses cleanly, so it stays a class.

  `alt` is required — an image without a text alternative doesn't ship;
  pass `alt=""` only for pure decoration.
  """
  use Phoenix.Component

  attr :src, :string, required: true
  attr :alt, :string, required: true, doc: ~s(Required. Use "" only for pure decoration.)
  attr :shape, :string, values: ~w(rect rounded circle pill), default: "rounded"
  attr :ratio, :string, default: nil, doc: ~s(CSS aspect-ratio for the frame, e.g. "16 / 10".)
  attr :class, :any, default: nil
  attr :rest, :global

  def treated_image(assigns) do
    ~H"""
    <figure
      class={["relative overflow-hidden m-0", shape_radius(@shape), @class]}
      style="border: var(--image-frame-border); outline: var(--image-frame-outline); mix-blend-mode: var(--image-blend)"
      {@rest}
    >
      <img src={@src} alt={@alt} class="block w-full h-full object-cover" style={img_style(@ratio)} />
      <span
        aria-hidden="true"
        class="absolute inset-0 pointer-events-none"
        style="background: var(--image-overlay); background-size: var(--image-overlay-size); mix-blend-mode: var(--image-overlay-blend)"
      />
    </figure>
    """
  end

  defp shape_radius("rect"), do: "rounded-none"
  defp shape_radius("rounded"), do: "rounded-[var(--radius-md)]"
  defp shape_radius("circle"), do: "rounded-[50%]"
  defp shape_radius("pill"), do: "rounded-[var(--radius-full)]"

  defp img_style(nil), do: "filter: var(--image-filter)"
  defp img_style(ratio), do: "aspect-ratio: #{ratio}; filter: var(--image-filter)"
end
