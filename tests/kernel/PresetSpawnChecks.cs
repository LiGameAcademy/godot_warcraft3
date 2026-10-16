using Rts.Game;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

internal static class PresetSpawnChecks
{
    internal static void Run(Action<bool, string> check)
    {
        var definition = new MovementDefinition(1, 270, 31, new MotionParameters());
        var grid = new PathingGrid(96, 96, 32, FixedVector2.Zero, new byte[96 * 96]);
        var heights = new TerrainHeights(25, 25, 128, FixedVector2.Zero, new SimScalar[625]);
        var match = new RtsMatch(MatchConfig.Default, 1, grid, heights, [definition]);
        var before = match.ComputeStateHash();
        var points = PresetSpawnLayout.Find(match, grid, definition, new FixedVector2(1536, 1536), 500);
        check(points.Count == 500 && points.Distinct().Count() == 500, "500 safe candidates are distinct");
        check(match.ComputeStateHash() == before, "candidate enumeration does not reserve or mutate match state");
        check(PresetSpawnLayout.Find(match, grid, definition, new FixedVector2(1536, 1536), 500).SequenceEqual(points),
            "repeating the same preset has stable positions");
        for (var i = 0; i < points.Count; i++)
            check(match.SubmitCommand(CommandEnvelope.Spawn(1, 0, i, points[i], 1)).Accepted, "candidate command is admitted");
        match.Step();
        check(match.Entities.Count == 500 && match.DrainEvents().All(item => item.Kind == MatchEventKind.EntitySpawned),
            "all 500 candidates pass real spawn collision checks at commit");
        var state = SnapshotJson.Serialize(match.CaptureSnapshot());
        check(RtsMatch.Restore(SnapshotJson.Deserialize(state), grid, heights, [definition]).ComputeStateHash()
            == match.ComputeStateHash(), "500 real bodies restore exactly");
        var tiny = new PathingGrid(1, 1, 32, FixedVector2.Zero, [0]);
        var blocked = new RtsMatch(MatchConfig.Default, 1, tiny, movementDefinitions: [definition]);
        before = blocked.ComputeStateHash();
        try { PresetSpawnLayout.Find(blocked, tiny, definition, new FixedVector2(16, 16), 1); check(false, "insufficient space rejects preset"); }
        catch (InvalidDataException) { check(blocked.ComputeStateHash() == before, "insufficient space leaves the old match intact"); }
    }
}
