using Godot;
using Rts.Kernel;

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
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error)
        {
            _lastError = error.Message;
            return false;
        }
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
            _match = RtsMatch.Restore(SnapshotJson.Deserialize(json));
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
