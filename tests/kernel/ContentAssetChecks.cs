using Rts.Content;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

internal static class ContentAssetChecks
{
    internal static void Run(string assetRoot, Action<bool, string> check)
    {
        string Read(string relative) => File.ReadAllText(Path.Combine(assetRoot, relative));
        var content = MatchContent.Read(Read("map-parsed/echoisles/pathing.json"), Read("map-parsed/echoisles/terrain-heightfield.json"),
            Read("slk-exported/Units/UnitData.json"), Read("slk-exported/Units/UnitBalance.json"), Read("map-parsed/echoisles/units.json"), []);
        var catalog = content.Units!;
        var starts = content.Starts;
        var grid = content.Grid;
        var terrain = content.Heights;
        check(catalog.TryGet("hfoo", out var foot) && foot?.Speed == 270 && foot.Radius == 31, "existing hfoo numbers reach the kernel exactly");
        check(catalog.TryGet("Hamg", out var hero) && hero?.Speed == 320 && hero.Radius == 32, "existing hero capability is retained");
        check(catalog.TryGet("eaoe", out var ancient) && ancient?.Radius == 144, "large moving ancient is admitted");
        check(starts.Count == 2 && starts[0].Position == new FixedVector2(-5184, 2944)
            && starts[1].Position == new FixedVector2(4672, 2944), "Echo Isles starts are read from sloc markers");
        check(catalog.Definitions.Count > 0 && catalog.Definitions.Count == catalog.GroundCodes.Count, "all supported definitions have content identity");
        var match = new RtsMatch(MatchConfig.Default, 14, grid, terrain, catalog.Definitions);
        foreach (var definition in catalog.Definitions)
            check(definition.Id != 0 && SimulationDomain.IsCapability(definition.Speed)
                && SimulationDomain.IsCapability(definition.Radius), "every admitted real profile fits the numeric contract");
        var snapshot = SnapshotJson.Serialize(match.CaptureSnapshot());
        var restored = RtsMatch.Restore(SnapshotJson.Deserialize(snapshot), grid, terrain, catalog.Definitions);
        check(restored.ComputeStateHash() == match.ComputeStateHash(), "real content, map and terrain restore under the same identity");
        Console.WriteLine($"Real content PASS: ground={catalog.Definitions.Count} excluded={catalog.ExcludedCount} starts={starts.Count} grid={grid.Width}x{grid.Height} maximumRadius={catalog.Definitions.Max(item => item.Radius)}; static WPM only, runtime footprints verified separately");
    }
}
