using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

namespace Rts.Game;

/// <summary>Diagnostic squad setup, not formation assignment. The kernel decides placement validity.</summary>
public static class PresetSpawnLayout
{
    public static IReadOnlyList<FixedVector2> Find(RtsMatch match, PathingGrid grid,
        MovementDefinition definition, FixedVector2 start, int count)
    {
        if (count is < 1 or > 500) throw new ArgumentOutOfRangeException(nameof(count));
        if (!grid.TryWorldToCell(start, out var center)) throw new InvalidDataException("Start marker is outside the pathing grid.");
        // Distinct lattice points are farther apart than two radii, including points not yet committed.
        var numerator = (Int128)definition.Radius.Raw * 2;
        var stride = checked((int)((numerator + grid.CellSize.Raw - 1) / grid.CellSize.Raw) + 1);
        var points = new List<FixedVector2>(count);
        var maximumRing = Math.Max(grid.Width, grid.Height) / stride + 1;
        for (var ring = 0; ring <= maximumRing; ring++)
        {
            foreach (var offset in Ring(ring))
            {
                var cell = new GridCell(center.X + offset.X * stride, center.Y + offset.Y * stride);
                if (!grid.Contains(cell)) continue;
                var point = new FixedVector2(
                    grid.Origin.X + grid.CellSize * cell.X + grid.CellSize / 2,
                    grid.Origin.Y + grid.CellSize * cell.Y + grid.CellSize / 2);
                if (!match.CanSpawn(point, definition.Id)) continue;
                points.Add(point);
                if (points.Count == count) return points.AsReadOnly();
            }
        }
        throw new InvalidDataException($"Only {points.Count} safe spawn positions are available for {count} units.");
    }

    private static IEnumerable<GridCell> Ring(int radius)
    {
        if (radius == 0) { yield return new GridCell(0, 0); yield break; }
        for (var x = -radius; x <= radius; x++)
        {
            yield return new GridCell(x, -radius);
            yield return new GridCell(x, radius);
        }
        for (var y = -radius + 1; y < radius; y++)
        {
            yield return new GridCell(-radius, y);
            yield return new GridCell(radius, y);
        }
    }
}
