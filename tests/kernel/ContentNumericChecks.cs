using Rts.Content;
using Rts.Kernel;
using Rts.Kernel.Numerics;

internal static class ContentNumericChecks
{
    internal static void Run(Action<bool, string> check)
    {
        var half = Math.ScaleB(1, -33);
        foreach (var sign in new[] { -1, 1 })
        {
            check(BinaryScalarInput.TryConvert(sign * half, out var tie) && tie.Raw == sign,
                "binary half quantum rounds away from zero exactly");
            check(BinaryScalarInput.TryConvert(sign * Math.BitDecrement(half), out var below) && below.Raw == 0,
                "binary value immediately below a tie rounds to zero");
            check(BinaryScalarInput.TryConvert(sign * Math.BitIncrement(half), out var above) && above.Raw == sign,
                "binary value immediately above a tie retains its sign");
        }
        check(BinaryScalarInput.TryConvert(-(double)(1L << 31), out var minimum) && minimum == SimScalar.MinValue,
            "negative scalar endpoint is representable");
        check(!BinaryScalarInput.TryConvert((double)(1L << 31), out _), "positive scalar overflow is rejected");
        check(!BinaryScalarInput.TryConvert(double.NaN, out _) && !BinaryScalarInput.TryConvert(double.PositiveInfinity, out _),
            "nonfinite binary inputs fail before command admission");
        check(BinaryScalarInput.TryConvert(double.Epsilon, out var tiny) && tiny == SimScalar.Zero,
            "subnormal input quantizes without a wide shift overflow");
        check(BinaryScalarInput.TryConvert((double)(float)0.1, out var binary) && binary.Raw == 429496736,
            "float transport preserves its binary value instead of reinterpreting a display decimal");
        var random = new DeterministicRng(14);
        for (var sample = 0; sample < 1024; sample++)
        {
            var whole = (long)(random.NextUInt64() & ((1UL << 50) - 1));
            var positive = Math.ScaleB(whole + 0.5, -32);
            check(BinaryScalarInput.TryConvert(positive, out var a) && a.Raw == whole + 1,
                "exactly constructed random binary half-quantum rounds up");
            check(BinaryScalarInput.TryConvert(-positive, out var b) && b.Raw == -whole - 1,
                "exactly constructed negative half-quantum rounds away from zero");
        }
        check(BinaryScalarInput.TryConvert(Math.BitDecrement((double)(1L << 31)), out var high)
            && high.Raw == long.MaxValue - 1023, "largest representable positive double inside scalar range is exact");
        check(!BinaryScalarInput.TryConvert(Math.BitDecrement(-(double)(1L << 31)), out _),
            "binary value below the negative scalar endpoint is rejected");
        var decimalGrid = ParsedTerrainReader.ReadPathing("""{"width":1,"height":1,"cellSize":0.1,"cells":[0]}""");
        check(decimalGrid.CellSize.Raw == 429496730, "authored decimal content quantizes directly from JSON text");
        var tieGrid = ParsedTerrainReader.ReadPathing("""{"width":1,"height":1,"cellSize":0.000000000116415321826934814453125,"cells":[0]}""");
        check(tieGrid.CellSize.Raw == 1, "JSON retains a full decimal tie without passing through double");
        try
        {
            ParsedTerrainReader.ReadPathing("""{"width":1,"height":1,"cellSize":0.000000000116415321826934814453124,"cells":[0]}""");
            check(false, "spacing below one raw quantum is rejected after quantization");
        }
        catch (ArgumentException) { check(true, "spacing below one raw quantum is rejected after quantization"); }
    }
}
