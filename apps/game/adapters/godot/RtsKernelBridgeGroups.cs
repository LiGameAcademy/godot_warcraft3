using Godot;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using System.Text.Json;

public partial class RtsKernelBridge
{
    [Signal]
    public delegate void GroupMoveResultRaisedEventHandler(long frame, long groupId, long entityId,
        int slot, Vector2 goal, bool assigned, bool adjusted, string reason);

    private IReadOnlyList<MovementDefinition>? _movementDefinitions;

    // Startup content boundary. Player commands cannot change these frozen capabilities.
    public bool ResetConfiguredNavigationMatch(int width, int height, double cellSize, Vector2 origin,
        byte[] flags, string movementDefinitionsJson, int tickRate, long seed)
    {
        try
        {
            var definitions = JsonSerializer.Deserialize<MovementDefinition[]>(movementDefinitionsJson,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? throw new ArgumentException("Movement definition array is required.");
            var grid = new PathingGrid(width, height, cellSize, new SimVector2(origin.X, origin.Y), flags);
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed), grid,
                movementDefinitions: definitions);
            _grid = grid;
            _terrain = null;
            _movementDefinitions = Array.AsReadOnly(definitions.ToArray());
            _match = match;
            _lastError = string.Empty;
            return true;
        }
        catch (Exception error) when (error is JsonException or ArgumentException)
        {
            return RejectInput(nameof(ResetConfiguredNavigationMatch), error);
        }
    }

    public Godot.Collections.Dictionary SubmitConfiguredSpawn(long executeFrame, int playerId, long sequence,
        Vector2 position, long movementDefinitionId)
    {
        if (movementDefinitionId <= 0) return Rejected("invalid_movement_definition_id");
        return ToResult(_match.SubmitCommand(CommandEnvelope.Spawn(executeFrame, playerId, sequence,
            new SimVector2(position.X, position.Y), (ulong)movementDefinitionId)));
    }

    public Godot.Collections.Dictionary SubmitGroupMove(long executeFrame, int playerId, long sequence,
        long[] entityIds, Vector2 goal, int formation, long leaderId, double heading, bool autoHeading,
        bool append, int source)
    {
        if (entityIds is null || entityIds.Any(id => id <= 0) || leaderId < 0)
            return Rejected("invalid_group_members");
        var request = new GroupMoveRequest(Array.AsReadOnly(entityIds.Select(id => new EntityId((ulong)id)).ToArray()),
            new SimVector2(goal.X, goal.Y), (FormationKind)formation, new EntityId((ulong)leaderId),
            autoHeading ? null : heading);
        return ToResult(_match.SubmitCommand(CommandEnvelope.MoveGroup(executeFrame, playerId, sequence, request,
            append ? OrderMode.Append : OrderMode.Replace, (OrderSource)source)));
    }

    public Godot.Collections.Array<Godot.Collections.Dictionary> ReadOrderViews()
    {
        var views = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var queue in _match.ReadUnitOrders())
        {
            var index = -1;
            foreach (var intent in queue.Pending.Prepend(queue.Current))
            {
                if (intent is not null)
                    views.Add(new Godot.Collections.Dictionary
                    {
                        ["entity_id"] = checked((long)queue.EntityId), ["queue_index"] = index,
                        ["kind"] = (int)intent.Kind, ["source"] = (int)intent.Source,
                        ["has_goal"] = intent.Move is not null,
                        ["goal"] = intent.Move is null ? Vector2.Zero : new Vector2((float)intent.Move.Goal.X, (float)intent.Move.Goal.Y),
                        ["group_id"] = checked((long)(intent.Group?.GroupId ?? 0)), ["slot"] = intent.Group?.Slot ?? -1,
                        ["formation"] = intent.Group is null ? -1 : (int)intent.Group.Formation,
                        ["adjusted"] = intent.Group?.Adjusted ?? false,
                    });
                index++;
            }
        }
        return views;
    }

    public Godot.Collections.Array<Godot.Collections.Dictionary> ReadGroupPlanViews()
    {
        var views = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var plan in _match.ReadGroupPlans())
            views.Add(new Godot.Collections.Dictionary
            {
                ["group_id"] = checked((long)plan.GroupId), ["members"] = plan.Members,
                ["canceled"] = plan.Canceled, ["matching_row"] = plan.MatchingRow,
            });
        return views;
    }

    public Godot.Collections.Array<Godot.Collections.Dictionary> ReadMovementViews()
    {
        var views = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        foreach (var move in _match.ReadMovementStatuses())
            views.Add(new Godot.Collections.Dictionary
            {
                ["entity_id"] = checked((long)move.EntityId), ["wait_frames"] = move.WaitFrames,
                ["retry_after_frame"] = move.RetryAfterFrame,
            });
        return views;
    }

}
