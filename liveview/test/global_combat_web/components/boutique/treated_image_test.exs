defmodule GlobalCombatWeb.Components.Boutique.TreatedImageTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias GlobalCombatWeb.Components.Boutique.TreatedImage

  test "renders an img with its alt inside a figure, treatment via theme vars" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TreatedImage.treated_image src="/brand-photos/nocturne.jpg" alt="Product photograph" />
      """)

    assert html =~ ~s(alt="Product photograph")
    assert html =~ "--image-filter"
    assert html =~ "--image-blend"
    # the overlay layer is decorative and hidden from AT
    assert html =~ ~s(aria-hidden="true")
    assert html =~ "--image-overlay"
  end

  test "maps shapes to radius tokens" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TreatedImage.treated_image src="/x.jpg" alt="" shape="pill" />
      """)

    assert html =~ "--radius-full"
  end

  test "applies the ratio prop to the image's aspect-ratio" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <TreatedImage.treated_image src="/x.jpg" alt="" ratio="16 / 10" />
      """)

    assert html =~ "aspect-ratio: 16 / 10"
  end

  test "alt is declared required — an image without a text alternative doesn't ship" do
    source = File.read!("lib/global_combat_web/components/boutique/treated_image.ex")
    assert source =~ ~r/attr :alt, :string, required: true/
  end

  test "references semantic tokens only — no literal hex/rgb/hsl colors in source" do
    source = File.read!("lib/global_combat_web/components/boutique/treated_image.ex")
    refute source =~ ~r/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/
  end
end
