defmodule GlobalCombat.Engine.GameTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.{DotnetRandom, Game}
  alias GlobalCombat.Engine.Game.{Area, Player}

  # Every expected value below was captured by actually resolving the equivalent turn against
  # the live .NET GrpcHost oracle (GIF-28's differential harness), not derived from reading
  # Game.cs and guessing — see the differential-harness skill's "the oracle is truth" rule.

  describe "do_attack/2" do
    test "matches the oracle for a decisive single attack (IsNonRandom: false)" do
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(999),
        is_non_random: false,
        minimum_armies: 3,
        areas: %{
          1 => %Area{
            number: 1,
            owner_number: 2,
            armies: 50,
            command: :attack,
            target_number: 2,
            amount: 49
          },
          2 => %Area{number: 2, owner_number: 1, armies: 30}
        },
        players: %{
          1 => %Player{number: 1, account_id: 1, name: "A", areas: 1},
          2 => %Player{number: 2, account_id: 2, name: "B", areas: 1}
        }
      }

      resolved = Game.do_attack(game, 1)

      assert Game.area!(resolved, 1).armies == 1
      assert Game.area!(resolved, 1).owner_number == 2
      assert Game.area!(resolved, 2).armies == 23
      assert Game.area!(resolved, 2).owner_number == 2
    end

    # Regression for the GIF-28 ReverseAttackOrder divergence: Game.cs only clamps (and only
    # possibly early-returns) when Amount *exceeds* Armies - 1. An order with Amount already at
    # or below that bound — including Amount == 0, a "no-op" order in AI-generated games — falls
    # through unchanged: the attack-roll loop then runs zero times, but the *defend*-roll loop
    # still runs its full `defender.Armies` draws regardless, since nothing gates it on the
    # attacker's amount. Skipping those draws (an earlier version of this port did, via an
    # `amount <= 0` short-circuit that looked equivalent but wasn't) desyncs every attack
    # processed after it in the same turn — invisible whenever the zero/near-zero order happens
    # to sort last (the default, descending order), but immediate under ReverseAttackOrder, where
    # small/zero orders sort first.
    test "an Amount-0 order still consumes the defender's roll draws, not zero draws" do
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(201_000_005),
        is_non_random: false,
        minimum_armies: 3,
        areas: %{
          9 => %Area{
            number: 9,
            owner_number: 3,
            armies: 13,
            command: :attack,
            target_number: 20,
            amount: 0
          },
          20 => %Area{number: 20, owner_number: 1, armies: 5}
        },
        players: %{
          1 => %Player{number: 1, account_id: 1, name: "A", areas: 1},
          3 => %Player{number: 3, account_id: 3, name: "C", areas: 1}
        }
      }

      resolved = Game.do_attack(game, 9)

      # State is unchanged either way (0 attack damage always, defend damage forced to 0 by the
      # `defendDamage > attacker.Amount` clamp) — the bug was invisible in isolation and only
      # showed up as *downstream* attacks in the same turn drawing the wrong numbers.
      assert Game.area!(resolved, 9).armies == 13
      assert Game.area!(resolved, 20).armies == 5

      # But 5 defend-roll draws (matching defender.Armies) must have been consumed — the next
      # draw off this rng should be the 6th draw from this seed, not the 1st.
      {roll6, _} = DotnetRandom.next(resolved.rng, 1, 5)
      {expected_roll6, _} = draw_n(DotnetRandom.new(201_000_005), 1, 5, 6)
      assert roll6 == expected_roll6
    end

    test "same_owner? short-circuits before consuming any draws" do
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(1),
        is_non_random: false,
        minimum_armies: 3,
        areas: %{
          1 => %Area{
            number: 1,
            owner_number: 1,
            armies: 10,
            command: :attack,
            target_number: 2,
            amount: 5
          },
          2 => %Area{number: 2, owner_number: 1, armies: 3}
        },
        players: %{1 => %Player{number: 1, account_id: 1, name: "A", areas: 2}}
      }

      resolved = Game.do_attack(game, 1)

      assert resolved.areas == game.areas
      assert resolved.rng == game.rng
    end
  end

  describe "reset_done_flags/1" do
    test "AccountId 1 is always done; eliminated players are always done; everyone else resets to false" do
      game = %Game{
        players: %{
          1 => %Player{number: 1, account_id: 1, name: "Computer", done: false, place: 0},
          2 => %Player{number: 2, account_id: 2, name: "Alice", done: true, place: 0},
          3 => %Player{number: 3, account_id: 3, name: "Bob", done: false, place: 2}
        }
      }

      resolved = Game.reset_done_flags(game)

      assert Game.player!(resolved, 1).done == true
      assert Game.player!(resolved, 2).done == false
      assert Game.player!(resolved, 3).done == true
    end
  end

  defp draw_n(rng, lo, hi, 1), do: DotnetRandom.next(rng, lo, hi)

  defp draw_n(rng, lo, hi, n) do
    {_, rng} = DotnetRandom.next(rng, lo, hi)
    draw_n(rng, lo, hi, n - 1)
  end
end
