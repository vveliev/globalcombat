defmodule GlobalCombat.Engine.DotnetRandomTest do
  use ExUnit.Case, async: true

  alias GlobalCombat.Engine.DotnetRandom, as: R

  # Every expected value below was captured by actually running `new Random(seed)`
  # on the same net10.0 runtime GlobalCombat.Core targets (dotnet 10.0.400), not
  # transcribed from documentation — see differential-harness skill: "never
  # hand-edit a captured output" / expected values must come from the oracle.

  test "Next() matches .NET for seed 12345 across a full 56-slot wraparound (60 draws)" do
    expected = [
      143_337_951,
      150_666_398,
      1_663_795_458,
      1_097_663_221,
      1_712_597_933,
      1_776_631_026,
      356_393_799,
      1_580_828_476,
      558_810_388,
      1_086_637_143,
      494_509_053,
      831_377_771,
      463_814_839,
      44_691_035,
      289_552_956,
      1_590_924_033,
      418_954_878,
      1_904_902_962,
      1_849_199_486,
      770_656_856,
      222_698_908,
      1_137_270_943,
      770_420_532,
      1_519_356_451,
      1_246_560_209,
      1_332_617_375,
      1_573_024_538,
      1_606_065_954,
      850_942_673,
      526_685_912,
      1_473_914_819,
      452_144_508,
      1_111_403_504,
      1_042_369_160,
      542_895_576,
      1_655_234_974,
      5_538_230,
      1_039_193_352,
      961_982_272,
      1_044_665_811,
      1_528_100_810,
      969_047_112,
      579_718_272,
      607_824_875,
      1_364_170_491,
      633_032_322,
      793_567_355,
      1_831_117_809,
      377_238_926,
      1_830_086_762,
      1_383_740_914,
      1_322_492_187,
      948_158_774,
      1_066_648_348,
      64_646_849,
      1_153_550_655,
      1_527_729_513,
      144_439_007,
      1_998_586_659,
      379_980_558
    ]

    assert draw(R.new(12345), length(expected), &R.next/1) == expected
  end

  test "Next() matches .NET for a negative seed" do
    expected = [
      1_351_050_993,
      2_024_055_590,
      122_460_634,
      1_691_463_017,
      516_012_789,
      1_251_539_877,
      1_105_241_021,
      1_341_954_554,
      1_225_211_290,
      1_408_858_799
    ]

    assert draw(R.new(-999), length(expected), &R.next/1) == expected
  end

  test "Next() matches .NET for Int32.MinValue seed (the Math.Abs edge case)" do
    expected = [1_559_595_546, 1_755_192_844, 1_649_316_172, 1_198_642_031, 442_452_829]

    assert draw(R.new(-2_147_483_648), length(expected), &R.next/1) == expected
  end

  test "Next(maxValue) matches .NET for seed 0" do
    expected = [30, 34, 32, 23, 8, 23, 38, 18, 41, 11]

    assert draw(R.new(0), length(expected), &R.next(&1, 42)) == expected
  end

  test "Next(minValue, maxValue) matches .NET — the exact call Game.cs makes for combat rolls" do
    expected = [6, 2, 1, 3, 5, 5, 2, 4, 6, 1, 1, 2, 1, 3, 2, 4, 6, 8, 1, 9]

    assert draw(R.new(999_999), length(expected), &R.next(&1, 1, 11)) == expected
  end

  test "sample/1 (NextDouble) matches .NET for seed 7" do
    expected = [
      0.38322046929189024,
      0.8712556827213874,
      0.6609386227377405,
      0.052261705534654534,
      0.36643333237917786
    ]

    assert draw(R.new(7), length(expected), &R.sample/1) == expected
  end

  defp draw(rng, count, fun) do
    {values, _rng} =
      Enum.map_reduce(1..count, rng, fn _, rng ->
        {v, rng} = fun.(rng)
        {v, rng}
      end)

    values
  end
end
