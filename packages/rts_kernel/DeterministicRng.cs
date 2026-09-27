namespace Rts.Kernel;

public sealed class DeterministicRng
{
    public DeterministicRng(ulong state)
    {
        State = state;
    }

    public ulong State { get; private set; }

    public ulong NextUInt64()
    {
        State += 0x9E3779B97F4A7C15UL;
        var value = State;
        value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9UL;
        value = (value ^ (value >> 27)) * 0x94D049BB133111EBUL;
        return value ^ (value >> 31);
    }
}
