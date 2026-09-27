using System.Text.Json;
using System.Globalization;

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

public readonly record struct SnapshotDifference(string Path, string Expected, string Actual);

public static class SnapshotValidator
{
    public static void Validate(MatchSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        if (snapshot.FormatVersion != SnapshotJson.CurrentFormatVersion)
        {
            throw new InvalidDataException($"Unsupported snapshot version: {snapshot.FormatVersion}.");
        }

        new MatchConfig(snapshot.TickRate).Validate();
        if (snapshot.Frame < 0 || snapshot.NextEntityId == 0
            || snapshot.NextArrivalOrder < 0 || snapshot.NextEventSequence < 0)
        {
            throw new InvalidDataException("Snapshot counters are outside their valid range.");
        }

        if (snapshot.Entities is null || snapshot.PendingCommands is null)
        {
            throw new InvalidDataException("Snapshot collections cannot be null.");
        }

        var entityIds = new HashSet<ulong>();
        ulong maximumEntityId = 0;
        foreach (var entity in snapshot.Entities)
        {
            if (entity.Id == 0 || entity.OwnerId < 0 || !entityIds.Add(entity.Id)
                || !double.IsFinite(entity.PositionX) || !double.IsFinite(entity.PositionY)
                || !double.IsFinite(entity.VelocityX) || !double.IsFinite(entity.VelocityY))
            {
                throw new InvalidDataException($"Invalid entity snapshot: {entity.Id}.");
            }

            maximumEntityId = Math.Max(maximumEntityId, entity.Id);
        }

        if (snapshot.NextEntityId <= maximumEntityId)
        {
            throw new InvalidDataException("Next entity id must be greater than every existing entity id.");
        }

        var arrivalOrders = new HashSet<long>();
        foreach (var queued in snapshot.PendingCommands)
        {
            var command = queued.Command
                ?? throw new InvalidDataException("Pending command cannot be null.");
            if (queued.ArrivalOrder < 0 || queued.ArrivalOrder >= snapshot.NextArrivalOrder
                || !arrivalOrders.Add(queued.ArrivalOrder))
            {
                throw new InvalidDataException($"Invalid pending arrival order: {queued.ArrivalOrder}.");
            }

            if (command.ExecuteFrame <= snapshot.Frame || command.PlayerId < 0 || command.Sequence < 0
                || !Enum.IsDefined(command.Kind)
                || !double.IsFinite(command.Position.X) || !double.IsFinite(command.Position.Y)
                || !double.IsFinite(command.Velocity.X) || !double.IsFinite(command.Velocity.Y))
            {
                throw new InvalidDataException("Invalid pending command.");
            }

            var expectsEntity = command.Kind is CommandKind.SetVelocity or CommandKind.Stop;
            if (expectsEntity == command.EntityId.IsNone)
            {
                throw new InvalidDataException("Pending command entity id does not match its kind.");
            }
        }
    }
}

public static class SnapshotDiff
{
    public static SnapshotDifference? FindFirst(MatchSnapshot expected, MatchSnapshot actual)
    {
        ArgumentNullException.ThrowIfNull(expected);
        ArgumentNullException.ThrowIfNull(actual);

        SnapshotDifference? difference;
        if ((difference = Compare("formatVersion", expected.FormatVersion, actual.FormatVersion)) is not null
            || (difference = Compare("tickRate", expected.TickRate, actual.TickRate)) is not null
            || (difference = Compare("frame", expected.Frame, actual.Frame)) is not null
            || (difference = Compare("nextEntityId", expected.NextEntityId, actual.NextEntityId)) is not null
            || (difference = Compare("nextArrivalOrder", expected.NextArrivalOrder, actual.NextArrivalOrder)) is not null
            || (difference = Compare("nextEventSequence", expected.NextEventSequence, actual.NextEventSequence)) is not null
            || (difference = Compare("rngState", expected.RngState, actual.RngState)) is not null
            || (difference = Compare("entities.count", expected.Entities.Count, actual.Entities.Count)) is not null)
        {
            return difference;
        }

        for (var index = 0; index < expected.Entities.Count; index++)
        {
            var left = expected.Entities[index];
            var right = actual.Entities[index];
            var prefix = $"entities[{index}]";
            if ((difference = Compare($"{prefix}.id", left.Id, right.Id)) is not null
                || (difference = Compare($"{prefix}.ownerId", left.OwnerId, right.OwnerId)) is not null
                || (difference = Compare($"{prefix}.positionX", left.PositionX, right.PositionX)) is not null
                || (difference = Compare($"{prefix}.positionY", left.PositionY, right.PositionY)) is not null
                || (difference = Compare($"{prefix}.velocityX", left.VelocityX, right.VelocityX)) is not null
                || (difference = Compare($"{prefix}.velocityY", left.VelocityY, right.VelocityY)) is not null)
            {
                return difference;
            }
        }

        if ((difference = Compare(
                "pendingCommands.count",
                expected.PendingCommands.Count,
                actual.PendingCommands.Count)) is not null)
        {
            return difference;
        }

        for (var index = 0; index < expected.PendingCommands.Count; index++)
        {
            var left = expected.PendingCommands[index];
            var right = actual.PendingCommands[index];
            var prefix = $"pendingCommands[{index}]";
            if ((difference = Compare($"{prefix}.arrivalOrder", left.ArrivalOrder, right.ArrivalOrder)) is not null
                || (difference = Compare($"{prefix}.executeFrame", left.Command.ExecuteFrame, right.Command.ExecuteFrame)) is not null
                || (difference = Compare($"{prefix}.playerId", left.Command.PlayerId, right.Command.PlayerId)) is not null
                || (difference = Compare($"{prefix}.sequence", left.Command.Sequence, right.Command.Sequence)) is not null
                || (difference = Compare($"{prefix}.kind", left.Command.Kind, right.Command.Kind)) is not null
                || (difference = Compare($"{prefix}.entityId", left.Command.EntityId, right.Command.EntityId)) is not null
                || (difference = Compare($"{prefix}.positionX", left.Command.Position.X, right.Command.Position.X)) is not null
                || (difference = Compare($"{prefix}.positionY", left.Command.Position.Y, right.Command.Position.Y)) is not null
                || (difference = Compare($"{prefix}.velocityX", left.Command.Velocity.X, right.Command.Velocity.X)) is not null
                || (difference = Compare($"{prefix}.velocityY", left.Command.Velocity.Y, right.Command.Velocity.Y)) is not null)
            {
                return difference;
            }
        }

        return null;
    }

    private static SnapshotDifference? Compare<T>(string path, T expected, T actual)
    {
        if (EqualityComparer<T>.Default.Equals(expected, actual))
        {
            return null;
        }

        return new SnapshotDifference(path, Format(expected), Format(actual));
    }

    private static string Format<T>(T value) => value switch
    {
        null => "null",
        double number => number.ToString("R", CultureInfo.InvariantCulture),
        IFormattable formattable => formattable.ToString(null, CultureInfo.InvariantCulture),
        _ => value.ToString() ?? string.Empty,
    };
}

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
