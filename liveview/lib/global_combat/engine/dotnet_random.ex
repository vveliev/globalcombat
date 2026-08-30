defmodule GlobalCombat.Engine.DotnetRandom do
  @moduledoc """
  Bit-for-bit reimplementation of .NET's seeded `System.Random(int seed)` —
  the "CompatPrng" Knuth-subtractive generator every .NET runtime still uses
  when a caller supplies an explicit seed (see
  `Random.CompatImpl.cs`/`CompatPrng` in dotnet/runtime; .NET only replaced
  the *unseeded* algorithm in .NET 6+, and explicitly kept this one for
  seeded reproducibility).

  `GlobalCombat.Core.Game.Rng` (`GlobalCombat.Core/Game.cs:160`, added for
  GIF-55) is exactly this constructor. The differential harness (GIF-28)
  depends on this module producing the identical draw sequence the .NET
  engine produces for the same seed — see `differential-harness` skill,
  "RNG determinism and seeding": same seed only means same sequence if it's
  literally the same algorithm, not just "also pseudorandom."

  Every function here takes and returns the generator state explicitly
  (Elixir has no mutable object to hide it behind, unlike `System.Random`).
  """

  @int_max_value 2_147_483_647
  @magic_seed 161_803_398

  defstruct [:seed_array, :inext, :inextp]

  @doc "Equivalent to `new Random(seed)` — builds the 56-slot subtractive seed array."
  def new(seed) when is_integer(seed) do
    subtraction = if seed == -2_147_483_648, do: @int_max_value, else: abs(seed)
    mj = @magic_seed - subtraction

    seed_array = List.to_tuple([0 | List.duplicate(0, 55)])
    seed_array = put_elem(seed_array, 55, mj)

    {seed_array, _mj, _mk, _ii} =
      Enum.reduce(1..54, {seed_array, mj, 1, 0}, fn _i, {arr, mj, mk, ii} ->
        ii = wrap55(ii + 21)
        arr = put_elem(arr, ii, mk)
        mk = wrap_positive(int32_sub(mj, mk))
        mj = elem(arr, ii)
        {arr, mj, mk, ii}
      end)

    seed_array =
      Enum.reduce(1..4, seed_array, fn _k, arr ->
        Enum.reduce(1..55, arr, fn i, arr ->
          n = if i + 30 >= 55, do: i + 30 - 55, else: i + 30
          value = wrap_positive(int32_sub(elem(arr, i), elem(arr, 1 + n)))
          put_elem(arr, i, value)
        end)
      end)

    %__MODULE__{seed_array: seed_array, inext: 0, inextp: 21}
  end

  defp wrap55(ii) when ii >= 55, do: ii - 55
  defp wrap55(ii), do: ii

  defp wrap_positive(v) when v < 0, do: v + @int_max_value
  defp wrap_positive(v), do: v

  # C#'s `int` subtraction wraps at 32 bits (unchecked, two's-complement overflow) — required by
  # this algorithm's own design (the seed array is built from `mj = 161803398 - subtraction`,
  # which for extreme seeds like `Int32.MinValue` starts far outside a normal int32's usual
  # working range, and only wraparound arithmetic reproduces what CompatPrng.Initialize actually
  # computes). Elixir integers are arbitrary-precision, so this has to be simulated explicitly —
  # verified against dotnet/runtime's actual `_seedArray` contents via reflection, not inferred:
  # without this, `new(-2_147_483_648)` diverges from real `Random(int.MinValue)` starting at the
  # 3rd draw. `wrap_positive/1`'s own single `+ int.MaxValue` correction (mirroring `if (mk < 0)
  # mk += int.MaxValue`) is applied by the caller *after* this, on the now-32-bit-correct value.
  defp int32_sub(a, b) do
    v = Bitwise.band(a - b, 0xFFFFFFFF)
    if v >= 0x80000000, do: v - 0x100000000, else: v
  end

  @doc "Equivalent to `Random.InternalSample()` — the raw generator step, range [0, int.MaxValue)."
  def internal_sample(%__MODULE__{} = rng) do
    loc_inext = wrap56(rng.inext + 1)
    loc_inextp = wrap56(rng.inextp + 1)

    ret_val = elem(rng.seed_array, loc_inext) - elem(rng.seed_array, loc_inextp)
    ret_val = if ret_val == @int_max_value, do: ret_val - 1, else: ret_val
    ret_val = wrap_positive(ret_val)

    seed_array = put_elem(rng.seed_array, loc_inext, ret_val)

    {ret_val, %{rng | seed_array: seed_array, inext: loc_inext, inextp: loc_inextp}}
  end

  defp wrap56(v) when v >= 56, do: 1
  defp wrap56(v), do: v

  @doc "Equivalent to `Random.Sample()` — a double in [0.0, 1.0)."
  def sample(%__MODULE__{} = rng) do
    {value, rng} = internal_sample(rng)
    {value * (1.0 / @int_max_value), rng}
  end

  @doc "Equivalent to `Random.Next()` — an int in [0, int.MaxValue)."
  def next(%__MODULE__{} = rng), do: internal_sample(rng)

  @doc "Equivalent to `Random.Next(maxValue)` — an int in [0, maxValue)."
  def next(%__MODULE__{} = rng, max_value) do
    {s, rng} = sample(rng)
    {trunc(s * max_value), rng}
  end

  @doc "Equivalent to `Random.Next(minValue, maxValue)` — an int in [minValue, maxValue)."
  def next(%__MODULE__{} = rng, min_value, max_value) do
    range = max_value - min_value
    {s, rng} = sample(rng)
    {trunc(s * range) + min_value, rng}
  end
end
