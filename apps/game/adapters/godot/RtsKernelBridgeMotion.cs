using Godot;
using Rts.Kernel;
using Rts.Kernel.Navigation;

public partial class RtsKernelBridge
{
    public bool ResetTerrainMatch(int width, int height, double cellSize, Vector2 origin,
        byte[] flags, int heightWidth, int heightHeight, double tileSize, Vector2 heightOrigin,
        double[] heights, int tickRate = 30, long seed = 1)
    {
        try
        {
            var grid = new PathingGrid(width, height, cellSize, new SimVector2(origin.X, origin.Y), flags);
            var terrain = new TerrainHeights(heightWidth, heightHeight, tileSize,
                new SimVector2(heightOrigin.X, heightOrigin.Y), heights);
            var match = new RtsMatch(new MatchConfig(tickRate), unchecked((ulong)seed), grid, terrain);
            _grid = grid;
            _terrain = terrain;
            _movementDefinitions = null;
            _match = match;
            _lastError = string.Empty;
            return true;
        }
        catch (ArgumentException error)
        {
            return RejectInput(nameof(ResetTerrainMatch), error);
        }
    }

    // Keep the original Godot-call arity; CLR optional defaults do not supply omitted call() arguments.
    public Godot.Collections.Dictionary SubmitMotionMoveTo(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells = 0,
        double turnRate = 0.5, bool scaleSlopeSpeed = true) =>
        SubmitMotionMoveOrder(executeFrame, playerId, sequence, entityId, goal, speed,
            clearanceCells, turnRate, scaleSlopeSpeed, false, 0);

    // Diagnostic entry only. Production movement must use frozen unit definitions, not client parameters.
    public Godot.Collections.Dictionary SubmitMotionMoveOrder(long executeFrame, int playerId, long sequence,
        long entityId, Vector2 goal, double speed, int clearanceCells,
        double turnRate, bool scaleSlopeSpeed, bool append, int source)
    {
        if (!TryEntityId(entityId, out var id)) return Rejected("invalid_entity_id");
        var motion = new MotionParameters(TurnRate: turnRate, ScaleSlopeSpeed: scaleSlopeSpeed);
        return ToResult(_match.SubmitCommand(CommandEnvelope.MoveTo(executeFrame, playerId, sequence,
            id, new SimVector2(goal.X, goal.Y), speed, clearanceCells, motion,
            append ? OrderMode.Append : OrderMode.Replace, (OrderSource)source)));
    }
}
