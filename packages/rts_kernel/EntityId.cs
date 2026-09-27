namespace Rts.Kernel;

public readonly record struct EntityId(ulong Value) : IComparable<EntityId>
{
    public static EntityId None => default;

    public bool IsNone => Value == 0;

    public int CompareTo(EntityId other) => Value.CompareTo(other.Value);

    public override string ToString() => Value.ToString(System.Globalization.CultureInfo.InvariantCulture);
}
