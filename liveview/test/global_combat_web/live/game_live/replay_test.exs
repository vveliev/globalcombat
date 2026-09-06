defmodule GlobalCombatWeb.GameLive.ReplayTest do
  use ExUnit.Case, async: true

  alias GlobalCombatWeb.GameLive.MapGeometry, as: Geometry
  alias GlobalCombatWeb.GameLive.Replay

  # Real :original-map areas (GlobalCombat.Engine.MapInfo) so `MapGeometry.label/2`
  # resolves real coordinates rather than raising on a made-up area number —
  # 31 = Ural, 26 = Ukraine, matching the issue's own worked example text.
  @ural 31
  @ukraine 26

  defp area(number, name, armies) do
    %{number: number, name: name, armies: armies}
  end

  defp areas(overrides \\ %{}) do
    [
      area(@ural, "Ural", Map.get(overrides, @ural, 3)),
      area(@ukraine, "Ukraine", Map.get(overrides, @ukraine, 6))
    ]
  end

  @players [%{number: 1, name: "Alice"}, %{number: 2, name: "Bob"}]

  describe "steps/4 with no events" do
    test "returns an empty list" do
      assert Replay.steps([], areas(), @players, :original) == []
    end
  end

  describe "steps/4 narration" do
    test "assign" do
      [step] = Replay.steps([{:assign, @ural, 5}], areas(), @players, :original)

      assert step.kind == :assign
      assert step.text == "Ural received 5 armies."
      assert step.from == nil
      assert step.to == nil
      assert step.captured == false
    end

    test "assign with a single army uses singular wording" do
      [step] = Replay.steps([{:assign, @ural, 1}], areas(), @players, :original)
      assert step.text == "Ural received 1 army."
    end

    test "transfer draws an arrow between the two areas' label anchors" do
      [step] = Replay.steps([{:transfer, @ural, @ukraine, 4}], areas(), @players, :original)

      assert step.kind == :transfer
      assert step.text == "Ural sent 4 armies to Ukraine."

      assert step.from == %{
               area: @ural,
               x: elem(Geometry.label(:original, @ural), 0),
               y: elem(Geometry.label(:original, @ural), 1)
             }

      assert step.to.area == @ukraine
      assert step.captured == false
    end

    test "a non-capturing attack" do
      [step] =
        Replay.steps(
          [{:attack, @ural, @ukraine, 12, 4, 6, false}],
          areas(),
          @players,
          :original
        )

      assert step.kind == :attack
      assert step.captured == false

      assert step.text ==
               "Ural attacked Ukraine with 12 armies: 4 lost, 6 defenders lost"
    end

    test "a capturing attack narrates the capture, matching the issue's worked example" do
      [step] =
        Replay.steps(
          [{:attack, @ural, @ukraine, 12, 4, 6, true}],
          areas(),
          @players,
          :original
        )

      assert step.captured == true

      assert step.text ==
               "Ural attacked Ukraine with 12 armies: 4 lost, 6 defenders lost, Ukraine captured"
    end

    test "eliminated and ended have no from/to but are still narrated" do
      steps =
        Replay.steps([{:eliminated, 2}, {:ended, 1}], areas(), @players, :original)

      assert [%{text: "Bob was eliminated.", from: nil, to: nil}, %{text: "Alice won the game."}] =
               steps
    end
  end

  describe "steps/4 running army counts" do
    test "a single touch on an area is exactly the area's known final count" do
      [step] = Replay.steps([{:assign, @ural, 5}], areas(%{@ural => 8}), @players, :original)
      assert step.counts == [%{area: @ural, value: 8}]
    end

    test "a chain of events on one area backfills every earlier step from the final count" do
      events = [
        # Ural: some unrelated area's events interleaved, then two touches on Ural.
        {:assign, @ural, 5},
        {:transfer, @ural, @ukraine, 2}
      ]

      # Final Ural armies (post +5, post -2) is 3 in the default fixture.
      steps = Replay.steps(events, areas(%{@ural => 3}), @players, :original)

      ural_counts = for %{counts: counts} <- steps, %{area: @ural, value: v} <- counts, do: v
      # After +5 from some earlier baseline, then -2, ending at 3: baseline was 0,
      # so the running values after each touch are [5, 3].
      assert ural_counts == [5, 3]
    end

    test "a capture pins the defender's post-event count exactly, independent of any final count" do
      [step] =
        Replay.steps(
          [{:attack, @ural, @ukraine, 12, 4, 6, true}],
          areas(%{@ukraine => 999}),
          @players,
          :original
        )

      ukraine_value = for %{area: area, value: v} <- step.counts, area == @ukraine, do: v
      # Survivors = amount - attacker_lost = 12 - 4 = 8, regardless of the area's
      # current (post-turn, possibly-fogged-again) final count.
      assert ukraine_value == [8]

      ural_value = for %{area: area, value: v} <- step.counts, area == @ural, do: v
      assert ural_value == [3]
    end

    test "nothing before a capture is backfilled past the ownership change" do
      events = [
        {:transfer, @ukraine, @ural, 2},
        {:attack, @ural, @ukraine, 12, 4, 6, true}
      ]

      steps = Replay.steps(events, areas(), @players, :original)
      [transfer_step, attack_step] = steps

      # The attack step's own counts still resolve (captured pin for Ukraine,
      # delta-from-that-pin's sibling area Ural).
      assert Enum.find(attack_step.counts, &(&1.area == @ukraine)).value == 8

      # But the *transfer* step touches Ukraine too, one step before the capture
      # flips its owner — that pre-capture count belongs to the old owner's pool
      # and is never inferrable from the post-capture survivor count, so it's
      # left out rather than guessed.
      refute Enum.any?(transfer_step.counts, &(&1.area == @ukraine))
    end

    test "an area with no currently-known final count (fogged again) gets no running counts" do
      areas_without_final = [
        area(@ural, "Ural", nil),
        area(@ukraine, "Ukraine", 6)
      ]

      [step] =
        Replay.steps([{:assign, @ural, 5}], areas_without_final, @players, :original)

      assert step.counts == []
    end
  end
end
