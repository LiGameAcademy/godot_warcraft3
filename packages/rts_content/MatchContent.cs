using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

namespace Rts.Content;

/// <summary>Immutable inputs retained by a host so snapshot restore uses exactly the same world.</summary>
public sealed class MatchContent
{
    public PathingGrid Grid { get; }
    public TerrainHeights? Heights { get; }
    public UnitMovementCatalog? Units { get; }
    public IReadOnlyList<MapStartLocation> Starts { get; }

    private MatchContent(PathingGrid grid, TerrainHeights? heights, UnitMovementCatalog? units,
        IReadOnlyList<MapStartLocation> starts)
    {
        Grid = grid;
        Heights = heights;
        Units = units;
        Starts = starts;
    }

    public static MatchContent Navigation(PathingGrid grid) => new(grid, null, null, Array.Empty<MapStartLocation>());

    public static MatchContent Read(string pathing, string heights, string unitData, string unitBalance,
        string placements, ReadOnlySpan<byte> runtimeFootprints)
    {
        var grid = ParsedTerrainReader.ReadPathing(pathing, runtimeFootprints);
        var terrain = ParsedTerrainReader.ReadHeights(heights);
        var maximum = new FixedVector2(grid.Origin.X + grid.CellSize * grid.Width,
            grid.Origin.Y + grid.CellSize * grid.Height);
        if (!terrain.TrySample(grid.Origin, out _) || !terrain.TrySample(maximum, out _))
            throw new InvalidDataException("Terrain heights must cover the whole pathing grid.");
        var starts = MapStartLocations.Read(placements);
        if (starts.Count == 0 || starts.Any(start => !grid.TryWorldToCell(start.Position, out _)))
            throw new InvalidDataException("Content needs in-map start markers.");
        return new MatchContent(grid, terrain, new UnitMovementCatalog(unitData, unitBalance), starts);
    }
}
