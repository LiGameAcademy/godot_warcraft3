namespace Rts.Kernel;

public readonly record struct SimVector2(double X, double Y)
{
    public static SimVector2 Zero => default;

    public static SimVector2 operator +(SimVector2 left, SimVector2 right) =>
        new(left.X + right.X, left.Y + right.Y);

    public static SimVector2 operator *(SimVector2 value, double scalar) =>
        new(value.X * scalar, value.Y * scalar);
}

public sealed record EntityState(
    EntityId Id,
    int OwnerId,
    SimVector2 Position,
    SimVector2 Velocity);

public sealed record MatchConfig(int TickRate)
{
    public static MatchConfig Default { get; } = new(30);

    public void Validate()
    {
        if (TickRate is < 1 or > 240)
        {
            throw new ArgumentOutOfRangeException(nameof(TickRate), "Tick rate must be between 1 and 240.");
        }
    }
}
