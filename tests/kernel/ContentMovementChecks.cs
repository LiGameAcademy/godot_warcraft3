using System.Text.Json;
using Rts.Content;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

internal static class ContentMovementChecks
{
    internal static void Run(Action<bool, string> check)
    {
        const string data = """{"records":[{"unitID":"hfoo","movetp":"foot","turnRate":0.6},{"unitID":"eaoe","movetp":"foot","turnRate":0.4},{"unitID":"hgry","movetp":"fly","turnRate":0.5},{"unitID":"hhou","movetp":"foot","turnRate":0.6}]}""";
        const string balance = """{"records":[{"unitBalanceID":"eaoe","spd":40,"collision":144,"isbldg":1},{"unitBalanceID":"hfoo","spd":270,"collision":31},{"unitBalanceID":"hhou","spd":"_","collision":48},{"unitBalanceID":"hgry","spd":350,"collision":32}]}""";
        var catalog = new UnitMovementCatalog(data, balance);
        check(catalog.TryGet("hfoo", out var foot) && foot is { Speed.Raw: 270L << 32, Radius.Raw: 31L << 32 }, "real-sized foot profile is read without host defaults");
        check(foot?.Motion?.TurnRate == SimScalar.Parse("0.6"), "turn rate is quantized directly from authored decimal");
        check(catalog.TryGet("eaoe", out var ancient) && ancient?.Radius == 144, "moving building capability is retained");
        check(!catalog.TryGet("hgry", out _) && catalog.ExclusionReason("hgry") == "unsupported_movement:fly", "air cannot silently become ground");
        check(catalog.ExclusionReason("hhou") == "no_movement_speed", "static profile is excluded explicitly");
        check(!catalog.TryGet("Hfoo", out _) && catalog.ExclusionReason("unknown") is null, "unit identity is case sensitive and unknown stays unknown");
        check(UnitMovementCatalog.DefinitionId("hfoo") == 0x68666f6fUL, "FourCC has explicit endian order");
        using var dataDocument = JsonDocument.Parse(data);
        using var balanceDocument = JsonDocument.Parse(balance);
        check(new UnitMovementCatalog(data, balance.Replace("\"_\"", "\"-\"")).ExclusionReason("hhou") == "no_movement_speed", "dash missing-value marker is also stationary");
        var shuffled = new UnitMovementCatalog(
            JsonSerializer.Serialize(new { records = dataDocument.RootElement.GetProperty("records").EnumerateArray().Reverse().ToArray() }),
            JsonSerializer.Serialize(new { records = balanceDocument.RootElement.GetProperty("records").EnumerateArray().Reverse().ToArray() }));
        var grid = new PathingGrid(32, 32, 32, new FixedVector2(-512, -512), new byte[1024]);
        var match = new RtsMatch(MatchConfig.Default, 1, grid, movementDefinitions: catalog.Definitions);
        var same = new RtsMatch(MatchConfig.Default, 1, grid, movementDefinitions: shuffled.Definitions);
        check(match.ComputeStateHash() == same.ComputeStateHash(), "content identity is deterministic");
        Reject(check, () => new UnitMovementCatalog(data, balance.Replace("270", "-1")), "negative speed fails catalog admission");
        Reject(check, () => new UnitMovementCatalog(data, balance.Replace("270", "65537")), "overflowing capability is rejected");
        Reject(check, () => new UnitMovementCatalog(data.Replace("0.6", "0.01"), balance), "invalid turn rate is not silently clamped");
        Reject(check, () => new UnitMovementCatalog(data.Replace("hfoo", "eaoe"), balance), "duplicate identity is rejected");
        Reject(check, () => UnitMovementCatalog.DefinitionId("bad"), "non-FourCC identity is rejected");
        var starts = MapStartLocations.Read("""{"units":[{"typeId":"sloc","owner":1,"position":{"x":0.1,"y":2}},{"typeId":"hfoo"},{"typeId":"sloc","owner":0,"position":{"x":-2,"y":3}}]}""");
        check(starts.Count == 2 && starts[0].PlayerId == 0 && starts[1].Position.X.Raw == 429496730, "starts are sorted and preserve decimal quantization");
        Reject(check, () => MapStartLocations.Read("""{"units":[{"typeId":"sloc","owner":10,"position":{"x":0,"y":0}}]}"""), "unsupported player marker is rejected");
        Reject(check, () => MapStartLocations.Read("""{"units":[{"typeId":"sloc","owner":0,"position":{"x":1048577,"y":0}}]}"""), "out-of-domain start is rejected");
    }

    private static void Reject(Action<bool, string> check, Action action, string message)
    {
        try { action(); check(false, message); }
        catch (InvalidDataException) { check(true, message); }
    }
}
