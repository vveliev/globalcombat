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

  describe "clear_assigned/2 (GIF-111, port of Game.ClearAssigned)" do
    test "returns the area's pending armies to the owner's unassigned pool and zeroes the area" do
      game = %Game{
        areas: %{1 => %Area{number: 1, owner_number: 1, armies: 10, assigned_armies: 4}},
        players: %{1 => %Player{number: 1, account_id: 1, name: "A", unassigned_armies: 6}}
      }

      {amount, resolved} = Game.clear_assigned(game, 1)

      assert amount == 4
      assert Game.area!(resolved, 1).assigned_armies == 0
      assert Game.player!(resolved, 1).unassigned_armies == 10
    end

    test "a no-op clear (nothing was ever assigned) returns 0 and leaves state untouched" do
      game = %Game{
        areas: %{1 => %Area{number: 1, owner_number: 1, armies: 10, assigned_armies: 0}},
        players: %{1 => %Player{number: 1, account_id: 1, name: "A", unassigned_armies: 6}}
      }

      {amount, resolved} = Game.clear_assigned(game, 1)

      assert amount == 0
      assert resolved == game
    end

    test "clamps a stale pending transfer/attack Amount down to the now-lower Armies - 1, matching Game.cs's defensive Math.Min" do
      game = %Game{
        areas: %{
          1 => %Area{
            number: 1,
            owner_number: 1,
            armies: 3,
            assigned_armies: 4,
            command: :attack,
            target_number: 2,
            # set while `assigned_armies` inflated this area's total to 7 (armies 3 +
            # assigned 4) -- clearing the assignment must clamp this back down too, or
            # the queued attack could spend armies the area no longer has.
            amount: 6
          }
        },
        players: %{1 => %Player{number: 1, account_id: 1, name: "A", unassigned_armies: 0}}
      }

      {_amount, resolved} = Game.clear_assigned(game, 1)

      assert Game.area!(resolved, 1).amount == 2
    end
  end

  describe "resolve_turn/1" do
    test "emits assign/transfer/attack events, in resolution order, alongside the resolved state" do
      # Player 1 owns areas 1 (reinforcing), 2/3 (transferring between them), and 5 (about to be
      # attacked and captured). Player 2 owns area 4 and attacks area 5 with `is_non_random: true`
      # so the outcome — and therefore the expected event — is arithmetic, not RNG-dependent.
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(1),
        is_non_random: true,
        minimum_armies: 0,
        areas: %{
          1 => %Area{number: 1, owner_number: 1, armies: 10, assigned_armies: 4},
          2 => %Area{
            number: 2,
            owner_number: 1,
            armies: 6,
            command: :transfer,
            target_number: 3,
            amount: 2
          },
          3 => %Area{number: 3, owner_number: 1, armies: 4},
          4 => %Area{
            number: 4,
            owner_number: 2,
            armies: 20,
            command: :attack,
            target_number: 5,
            amount: 19
          },
          5 => %Area{number: 5, owner_number: 1, armies: 5}
        },
        players: %{
          1 => %Player{number: 1, account_id: 2, name: "A", areas: 4},
          2 => %Player{number: 2, account_id: 3, name: "B", areas: 1}
        }
      }

      {resolved, events} = Game.resolve_turn(game)

      # attack_damage = trunc(19 * 0.6) = 11, capped to defender.armies (5) = 5.
      # defend_damage = trunc(5 * 0.75) = 3, capped to amount (19) = 3.
      # captured?: attack_damage (5) >= defender.armies (5) and defend_damage (3) < amount (19).
      assert events == [
               {:assign, 1, 4},
               {:transfer, 2, 3, 2},
               {:attack, 4, 5, 19, 3, 5, true}
             ]

      assert Game.area!(resolved, 1).armies == 14
      assert Game.area!(resolved, 2).armies == 4
      assert Game.area!(resolved, 3).armies == 6
      assert Game.area!(resolved, 5).armies == 16
      assert Game.area!(resolved, 5).owner_number == 2
      assert Game.player!(resolved, 1).areas == 3
      assert Game.player!(resolved, 2).areas == 2
    end

    test "emits :eliminated then :ended when a captured area leaves its owner with none left" do
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(1),
        is_non_random: true,
        minimum_armies: 0,
        areas: %{
          1 => %Area{
            number: 1,
            owner_number: 1,
            armies: 20,
            command: :attack,
            target_number: 2,
            amount: 19
          },
          2 => %Area{number: 2, owner_number: 2, armies: 5}
        },
        players: %{
          1 => %Player{number: 1, account_id: 2, name: "A", areas: 1},
          2 => %Player{number: 2, account_id: 3, name: "B", areas: 1}
        }
      }

      {resolved, events} = Game.resolve_turn(game)

      assert events == [
               {:attack, 1, 2, 19, 3, 5, true},
               {:eliminated, 2},
               {:ended, 1}
             ]

      assert resolved.ended
      assert Game.player!(resolved, 1).place == 1
    end

    test "run_turn/1 still returns only the resolved state, unaffected by resolve_turn/1's event log" do
      # Two still-standing players (not one) — a single-player game would hit `end_game/1`'s
      # `alive_players <= 1` path here, which this test isn't exercising.
      game = %Game{
        map_name: :original,
        rng: DotnetRandom.new(1),
        is_non_random: true,
        minimum_armies: 0,
        areas: %{
          1 => %Area{number: 1, owner_number: 1, armies: 10, assigned_armies: 4},
          2 => %Area{number: 2, owner_number: 2, armies: 5}
        },
        players: %{
          1 => %Player{number: 1, account_id: 2, name: "A", areas: 1},
          2 => %Player{number: 2, account_id: 3, name: "B", areas: 1}
        }
      }

      {resolve_result, events} = Game.resolve_turn(game)
      assert events == [{:assign, 1, 4}]
      assert Game.area!(resolve_result, 1).armies == 14
      assert Game.run_turn(game) == resolve_result
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
