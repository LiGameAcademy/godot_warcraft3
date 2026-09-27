using System.Text.Json;

namespace Rts.Kernel;

public sealed record EntitySnapshot(
    ulong Id,
    int OwnerId,
    double PositionX,
    double PositionY,
    double VelocityX,
    double VelocityY);

public sealed record QueuedCommandSnapshot(long ArrivalOrder, CommandEnvelope Command);

public sealed record MatchSnapshot(
    int FormatVersion,
    int TickRate,
    long Frame,
    ulong NextEntityId,
    long NextArrivalOrder,
    long NextEventSequence,
    ulong RngState,
    IReadOnlyList<EntitySnapshot> Entities,
    IReadOnlyList<QueuedCommandSnapshot> PendingCommands);

public static class SnapshotJson
{
    public const int CurrentFormatVersion = 1;

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    public static string Serialize(MatchSnapshot snapshot) => JsonSerializer.Serialize(snapshot, Options);

    public static MatchSnapshot Deserialize(string json) =>
        JsonSerializer.Deserialize<MatchSnapshot>(json, Options)
        ?? throw new InvalidDataException("Snapshot JSON did not contain a match snapshot.");
}
