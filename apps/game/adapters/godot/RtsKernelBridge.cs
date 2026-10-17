using Godot;
using System.Text.Json;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;
using Rts.Content;
using Rts.Game;

/// <summary>
/// The single Godot-facing boundary for the engine-independent RTS simulation.
/// It accepts immutable command data and returns copied presentation views.
/// </summary>
public partial class RtsKernelBridge : Node
{
    [Signal]
    public delegate void MatchEventRaisedEventHandler(
        long frame,
        long sequence,
        int kind,
        long entityId,
        string detail);

    private RtsMatch _match = new(MatchConfig.Default, seed: 1);
    private MatchContent? _content;
    private string _lastError = string.Empty;

    public long GetFrame() => _match.Frame;

    public int GetTickRate() => _match.Config.TickRate;

    public string GetLastError() => _lastError;

    public string GetStateHash() => _match.ComputeStateHash();

    /// <summary>Loading-time work only; safe between steps and after navigation edits.</summary>
    public double PrepareForPlay() => PrepareMatch(_match, "explicit");

    private static double PrepareMatch(RtsMatch match, string context)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        match.PrepareForPlay();
        watch.Stop();
        GD.Print($"[RTS preparation] context={context} frame={match.Frame} elapsed_ms={watch.Elapsed.TotalMilliseconds:F3}");
        return watch.Elapsed.TotalMilliseconds;
    }

    public bool ResetMatch(int tickRate = 30, long seed = 1)
    {
        try
        {
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed));
            PrepareMatch(match, "new-match");
            _match = match;
            _content = null;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error) when (error is ArgumentException or InvalidDataException or OverflowException or FormatException or JsonException)
        {
            _lastError = error.Message;
            return false;
        }
    }

    public bool ResetNavigationMatch(int width, int height, double cellSize, Vector2 origin,
        byte[] flags, int tickRate = 30, long seed = 1)
    {
        if (!BinaryScalarInput.TryConvert(cellSize, out var fixedCellSize) || !TryVector(origin, out var fixedOrigin))
        {
            _lastError = "invalid_numeric_input";
            return false;
        }
        try
        {
            var grid = new PathingGrid(width, height, fixedCellSize, fixedOrigin, flags);
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed), grid);
            PrepareMatch(match, "new-navigation-match");
            _content = MatchContent.Navigation(grid);
            _match = match;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error) when (error is ArgumentException or InvalidDataException or OverflowException or FormatException or JsonException)
        {
            _lastError = error.Message;
            return false;
        }
    }

    public bool ResetContentMatch(string pathing, string heights, string unitData, string unitBalance,
        string placements, byte[] runtimeFootprints, int tickRate, long seed)
    {
        try
        {
            var content = MatchContent.Read(pathing, heights, unitData, unitBalance, placements, runtimeFootprints);
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed), content.Grid,
                content.Heights, content.Units!.Definitions);
            PrepareMatch(match, "new-content-match");
            _content = content;
            _match = match;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error) when (error is ArgumentException or InvalidDataException or OverflowException
            or FormatException or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            _lastError = error.Message;
            return false;
        }
    }

    public Godot.Collections.Dictionary SpawnPreset(string unitCode, int count, int playerId)
    {
        if (_content?.Units is null || _match.Frame != 0 || _match.Entities.Count != 0 || _match.CaptureSnapshot().PendingCommands.Count != 0)
            return Rejected("preset_requires_fresh_content_match");
        if (!_content.Units.TryGet(unitCode, out var definition)) return Rejected("unsupported_unit_profile");
        var start = _content.Starts.FirstOrDefault(item => item.PlayerId == playerId);
        if (start is null) return Rejected("start_marker_missing");
        try
        {
            var points = PresetSpawnLayout.Find(_match, _content.Grid, definition!, start.Position, count);
            var candidate = new RtsMatch(_match.Config, _match.CaptureSnapshot().RngState, _content.Grid,
                _content.Heights, _content.Units.Definitions);
            PrepareMatch(candidate, "preset-match");
            for (var index = 0; index < points.Count; index++)
            {
                var accepted = candidate.SubmitCommand(CommandEnvelope.Spawn(1, playerId, index, points[index], definition!.Id));
                if (!accepted.Accepted) throw new InvalidOperationException(accepted.Error);
            }
            candidate.Step();
            if (candidate.Entities.Count != count) throw new InvalidOperationException("Validated preset spawn failed during commit.");
            _match = candidate;
            EmitPendingEvents();
            return ToResult(CommandAcceptance.Accept());
        }
        catch (Exception error) when (error is ArgumentException or InvalidDataException or OverflowException)
        {
            return Rejected(error.Message);
        }
    }

    public Godot.Collections.Dictionary SubmitGroupMove(long executeFrame, int playerId, long sequence,
        long[] entityIds, Vector2 goal, int formation, bool append)
    {
        if (entityIds.Length is < 1 or > 500) return Rejected("invalid_group_size");
        if (entityIds.Any(id => id <= 0)) return Rejected("invalid_entity_id");
        if (!TryVector(goal, out var fixedGoal)) return Rejected("invalid_numeric_input");
        var members = entityIds.Select(id => new EntityId((ulong)id)).ToArray();
        return ToResult(_match.SubmitCommand(CommandEnvelope.MoveGroup(executeFrame, playerId, sequence,
            new GroupMoveRequest(members, fixedGoal, (FormationKind)formation),
            append ? OrderMode.Append : OrderMode.Replace)));
    }

    public Godot.Collections.Dictionary ReadMovementFrame() => RtsMovementFrame.Read(_match, _content?.Heights);

    public Godot.Collections.Dictionary SubmitMoveTo(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells = 0) =>
        SubmitMoveOrder(executeFrame, playerId, sequence, entityId, goal, speed, clearanceCells, false);

    public Godot.Collections.Dictionary SubmitMoveOrder(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells, bool append)
    {
        if (!TryEntityId(entityId, out var id)) return Rejected("invalid_entity_id");
        if (!TryVector(goal, out var fixedGoal) || !BinaryScalarInput.TryConvert(speed, out var fixedSpeed))
            return Rejected("invalid_numeric_input");
        return ToResult(_match.SubmitCommand(CommandEnvelope.MoveTo(executeFrame, playerId, sequence,
            id, fixedGoal, fixedSpeed, clearanceCells, mode: append ? OrderMode.Append : OrderMode.Replace)));
    }

    public Godot.Collections.Dictionary SubmitSetObstacle(long executeFrame, int playerId, long sequence,
        long obstacleId, Rect2I area)
    {
        if (obstacleId <= 0) return Rejected("invalid_obstacle_id");
        return ToResult(_match.SubmitCommand(CommandEnvelope.SetObstacle(executeFrame, playerId, sequence,
            (ulong)obstacleId, new GridArea(area.Position.X, area.Position.Y, area.Size.X, area.Size.Y))));
    }

    public Godot.Collections.Dictionary SubmitRemoveObstacle(long executeFrame, int playerId, long sequence, long obstacleId)
    {
        if (obstacleId <= 0) return Rejected("invalid_obstacle_id");
        return ToResult(_match.SubmitCommand(CommandEnvelope.RemoveObstacle(executeFrame, playerId, sequence, (ulong)obstacleId)));
    }

    public Godot.Collections.Dictionary SubmitSpawn(
        long executeFrame,
        int playerId,
        long sequence,
        Vector2 position)
    {
        if (!TryVector(position, out var fixedPosition)) return Rejected("invalid_numeric_input");
        return ToResult(_match.SubmitCommand(CommandEnvelope.Spawn(executeFrame, playerId, sequence, fixedPosition)));
    }

    public Godot.Collections.Dictionary SubmitVelocity(
        long executeFrame,
        int playerId,
        long sequence,
        long entityId,
        Vector2 velocity)
    {
        if (!TryEntityId(entityId, out var id))
        {
            return Rejected("invalid_entity_id");
        }

        if (!TryVector(velocity, out var fixedVelocity)) return Rejected("invalid_numeric_input");
        return ToResult(_match.SubmitCommand(CommandEnvelope.SetVelocity(
            executeFrame,
            playerId,
            sequence,
            id,
            fixedVelocity)));
    }

    public Godot.Collections.Dictionary SubmitStop(
        long executeFrame,
        int playerId,
        long sequence,
        long entityId)
    {
        if (!TryEntityId(entityId, out var id))
        {
            return Rejected("invalid_entity_id");
        }

        return ToResult(_match.SubmitCommand(CommandEnvelope.Stop(
            executeFrame,
            playerId,
            sequence,
            id)));
    }

    public bool Step(int count = 1)
    {
        if (count is < 1 or > 10_000)
        {
            _lastError = "step_count_must_be_between_1_and_10000";
            return false;
        }

        for (var index = 0; index < count; index++)
        {
            _match.Step();
            EmitPendingEvents();
        }

        _lastError = string.Empty;
        return true;
    }

    public Godot.Collections.Array<Godot.Collections.Dictionary> ReadEntityViews()
    {
        var views = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var entity in _match.Entities)
        {
            views.Add(new Godot.Collections.Dictionary
            {
                ["id"] = checked((long)entity.Id.Value),
                ["owner_id"] = entity.OwnerId,
                ["moving"] = _match.IsMoving(entity.Id),
                ["position"] = new Vector2((float)entity.Position.X.ToPresentationDouble(), (float)entity.Position.Y.ToPresentationDouble()),
                ["velocity"] = new Vector2((float)entity.Velocity.X.ToPresentationDouble(), (float)entity.Velocity.Y.ToPresentationDouble()),
            });
        }

        return views;
    }

    public string CaptureSnapshotJson() => SnapshotJson.Serialize(_match.CaptureSnapshot());

    public bool RestoreSnapshotJson(string json)
    {
        try
        {
            var snapshot = SnapshotJson.Deserialize(json);
            var restored = RtsMatch.Restore(snapshot, snapshot.Navigation is null ? null : _content?.Grid,
                snapshot.Navigation is null ? null : _content?.Heights,
                snapshot.Navigation is null ? null : _content?.Units?.Definitions);
            PrepareMatch(restored, "restored-match");
            _match = restored;
            if (snapshot.Navigation is null) _content = null;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error) when (error is ArgumentException or InvalidDataException or OverflowException or FormatException or JsonException)
        {
            _lastError = error.Message;
            return false;
        }
    }

    private void EmitPendingEvents()
    {
        foreach (var matchEvent in _match.DrainEvents())
        {
            EmitSignal(
                SignalName.MatchEventRaised,
                matchEvent.Frame,
                matchEvent.Sequence,
                (int)matchEvent.Kind,
                checked((long)matchEvent.EntityId.Value),
                matchEvent.Detail);
        }
    }

    private Godot.Collections.Dictionary ToResult(CommandAcceptance acceptance)
    {
        _lastError = acceptance.Error;
        return new Godot.Collections.Dictionary
        {
            ["accepted"] = acceptance.Accepted,
            ["error"] = acceptance.Error,
        };
    }

    private Godot.Collections.Dictionary Rejected(string error)
    {
        _lastError = error;
        return new Godot.Collections.Dictionary
        {
            ["accepted"] = false,
            ["error"] = error,
        };
    }

    private static bool TryVector(Vector2 value, out FixedVector2 result)
    {
        result = default;
        if (!BinaryScalarInput.TryConvert(value.X, out var x) || !BinaryScalarInput.TryConvert(value.Y, out var y))
            return false;
        result = new FixedVector2(x, y);
        return true;
    }

    private static bool TryEntityId(long value, out EntityId entityId)
    {
        entityId = value > 0 ? new EntityId((ulong)value) : EntityId.None;
        return !entityId.IsNone;
    }
}
