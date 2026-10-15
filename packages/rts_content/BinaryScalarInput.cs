using Rts.Kernel.Numerics;

namespace Rts.Content;

/// <summary>Host transport boundary: exact IEEE754 input to raw32.32, nearest/ties away from zero.</summary>
public static class BinaryScalarInput
{
    public static bool TryConvert(double input, out SimScalar value)
    {
        value = default;
        var bits = unchecked((ulong)BitConverter.DoubleToInt64Bits(input));
        var exponent = (int)((bits >> 52) & 0x7ff);
        if (exponent == 0x7ff) return false;
        var negative = (bits >> 63) != 0;
        var mantissa = bits & ((1UL << 52) - 1);
        if (exponent != 0) mantissa |= 1UL << 52;
        var shift = exponent == 0 ? -1042 : exponent - 1043;
        UInt128 magnitude;
        if (shift >= 0)
        {
            if (shift > 63) return false;
            magnitude = (UInt128)mantissa << shift;
        }
        else
        {
            var discardedBits = -shift;
            if (discardedBits >= 64) magnitude = 0;
            else
            {
                var whole = mantissa >> discardedBits;
                var remainder = mantissa & ((1UL << discardedBits) - 1);
                if (remainder >= (1UL << (discardedBits - 1))) whole++;
                magnitude = whole;
            }
        }
        var limit = negative ? (UInt128)1 << 63 : (UInt128)long.MaxValue;
        if (magnitude > limit) return false;
        value = negative && magnitude == ((UInt128)1 << 63) ? SimScalar.MinValue
            : SimScalar.FromRaw(negative ? -(long)magnitude : (long)magnitude);
        return true;
    }
}
