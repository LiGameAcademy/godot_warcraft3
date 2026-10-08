using Godot;
using Rts.Kernel;
using Rts.Kernel.Navigation;

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
    private PathingGrid? _grid;
    private TerrainHeights? _terrain;
    private string _lastError = string.Empty;

    public long GetFrame() => _match.Frame;

    public int GetTickRate() => _match.Config.TickRate;

    public string GetLastError() => _lastError;

    public string GetStateHash() => _match.ComputeStateHash();

    public bool ResetMatch(int tickRate = 30, long seed = 1)
    {
        try
        {
            _match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed));
            _grid = null;
            _terrain = null;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error)
        {
            _lastError = error.Message;
            return false;
        }
    }

    public bool ResetNavigationMatch(int width, int height, double cellSize, Vector2 origin,
        byte[] flags, int tickRate = 30, long seed = 1)
    {
        try
        {
            var grid = new PathingGrid(width, height, cellSize, new SimVector2(origin.X, origin.Y), flags);
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed), grid);
            _grid = grid;
            _terrain = null;
            _match = match;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error)
        {
            _lastError = error.Message;
            return false;
        }
    }

    public Godot.Collections.Dictionary SubmitMoveTo(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells = 0) =>
        SubmitMoveOrder(executeFrame, playerId, sequence, entityId, goal, speed, clearanceCells, false, 0);

    public Godot.Collections.Dictionary SubmitMoveOrder(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells, bool append, int source)
    {
        if (!TryEntityId(entityId, out var id)) return Rejected("invalid_entity_id");
        return ToResult(_match.SubmitCommand(CommandEnvelope.MoveTo(executeFrame, playerId, sequence,
            id, new SimVector2(goal.X, goal.Y), speed, clearanceCells,
            mode: append ? OrderMode.Append : OrderMode.Replace, source: (OrderSource)source)));
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
        Vector2 position) =>
        ToResult(_match.SubmitCommand(CommandEnvelope.Spawn(
            executeFrame,
            playerId,
            sequence,
            new SimVector2(position.X, position.Y))));

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

        return ToResult(_match.SubmitCommand(CommandEnvelope.SetVelocity(
            executeFrame,
            playerId,
            sequence,
            id,
            new SimVector2(velocity.X, velocity.Y))));
    }

    public Godot.Collections.Dictionary SubmitStop(long executeFrame, int playerId, long sequence, long entityId) =>
        SubmitOrderStop(executeFrame, playerId, sequence, entityId, 0);

    public Godot.Collections.Dictionary SubmitOrderStop(long executeFrame, int playerId, long sequence,
        long entityId, int source)
    {
        if (!TryEntityId(entityId, out var id)) return Rejected("invalid_entity_id");
        return ToResult(_match.SubmitCommand(CommandEnvelope.Stop(executeFrame, playerId, sequence, id, (OrderSource)source)));
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
            var order = _match.ReadCurrentOrder(entity.Id);
            views.Add(new Godot.Collections.Dictionary
            {
                ["id"] = checked((long)entity.Id.Value),
                ["owner_id"] = entity.OwnerId,
                ["moving"] = _match.IsMoving(entity.Id),
                ["facing"] = entity.Facing,
                ["order_kind"] = order is null ? 0 : (int)order.Kind,
                ["order_source"] = order is null ? -1 : (int)order.Source,
                ["pending_orders"] = _match.GetPendingOrderCount(entity.Id),
                ["position"] = new Vector2((float)entity.Position.X, (float)entity.Position.Y),
                ["velocity"] = new Vector2((float)entity.Velocity.X, (float)entity.Velocity.Y),
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
            _match = RtsMatch.Restore(snapshot, snapshot.Navigation is null ? null : _grid,
                snapshot.Navigation?.HeightHash is null ? null : _terrain);
            if (snapshot.Navigation is null) _grid = null;
            if (snapshot.Navigation?.HeightHash is null) _terrain = null;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error)
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

    private static bool TryEntityId(long value, out EntityId entityId)
    {
        entityId = value > 0 ? new EntityId((ulong)value) : EntityId.None;
        return !entityId.IsNone;
    }
}
