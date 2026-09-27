namespace Rts.Kernel;

public enum CommandKind
{
    SpawnEntity = 1,
    SetVelocity = 2,
    Stop = 3,
}

public sealed record CommandEnvelope(
    long ExecuteFrame,
    int PlayerId,
    long Sequence,
    CommandKind Kind,
    EntityId EntityId,
    SimVector2 Position,
    SimVector2 Velocity)
{
    public static CommandEnvelope Spawn(
        long executeFrame,
        int playerId,
        long sequence,
        SimVector2 position) =>
        new(executeFrame, playerId, sequence, CommandKind.SpawnEntity, EntityId.None, position, SimVector2.Zero);

    public static CommandEnvelope SetVelocity(
        long executeFrame,
        int playerId,
        long sequence,
        EntityId entityId,
        SimVector2 velocity) =>
        new(executeFrame, playerId, sequence, CommandKind.SetVelocity, entityId, SimVector2.Zero, velocity);

    public static CommandEnvelope Stop(
        long executeFrame,
        int playerId,
        long sequence,
        EntityId entityId) =>
        new(executeFrame, playerId, sequence, CommandKind.Stop, entityId, SimVector2.Zero, SimVector2.Zero);
}

public readonly record struct CommandAcceptance(bool Accepted, string Error)
{
    public static CommandAcceptance Accept() => new(true, string.Empty);

    public static CommandAcceptance Reject(string error) => new(false, error);
}

public enum MatchEventKind
{
    EntitySpawned = 1,
    CommandRejected = 2,
}

public sealed record MatchEvent(
    long Frame,
    long Sequence,
    MatchEventKind Kind,
    EntityId EntityId,
    string Detail);

internal sealed record QueuedCommand(long ArrivalOrder, CommandEnvelope Command);
