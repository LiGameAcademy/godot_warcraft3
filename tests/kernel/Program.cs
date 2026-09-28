using Rts.Kernel;
using Rts.Content;
using Rts.Kernel.Navigation;

// Game-owned format checks. Pure tests are in external/rts_kernel.
var checks = 0;
void Check(bool condition, string message)
{
    checks++;
    if (!condition) throw new InvalidOperationException(message);
}
var fromArray = ParsedTerrainReader.ReadPathing("""{"width":2,"height":2,"cells":[0,2,4,8]}""");
var fromBase64 = ParsedTerrainReader.ReadPathing("""{"width":2,"height":2,"cellsBase64":"AAIECA=="}""");
Check(fromArray.FlagsAt(new GridCell(1, 1)) == fromBase64.FlagsAt(new GridCell(1, 1)), "pathing encodings equivalent");
var terrain = ParsedTerrainReader.ReadHeights("""{"tilepointWidth":2,"tilepointHeight":2,"tileSize":128,"centerOffset":{"x":-128,"y":-128},"heights":[0,10,20,30]}""");
Check(terrain.TrySample(new SimVector2(-64, -64), out var altitude) && altitude == 15, "bilinear height sample");
Check(terrain.TrySample(SimVector2.Zero, out altitude) && altitude == 30, "last corner samples final quad");
Check(!terrain.TrySample(new SimVector2(1, 0), out _), "height outside map explicitly missing");

Console.WriteLine($"Rts.Content integration PASS ({checks} checks)");
