namespace Rts.Kernel.Navigation;

public readonly record struct GridCell(int X, int Y);

/// <summary>Immutable row-major grid in WC3 coordinates; hosts cannot mutate its buffers.</summary>
public sealed class PathingGrid
{
    private readonly byte[] _flags;
    public int Width { get; }
    public int Height { get; }
    public double CellSize { get; }
    public SimVector2 Origin { get; }

    public PathingGrid(int width, int height, double cellSize, SimVector2 origin,
        ReadOnlySpan<byte> flags, ReadOnlySpan<byte> obstacleFlags = default)
    {
        TerrainValidation.Grid(width, height, cellSize, origin);
        if (flags.Length != checked(width * height)
            || (!obstacleFlags.IsEmpty && obstacleFlags.Length != flags.Length))
            throw new ArgumentException("Pathing buffer length must match grid dimensions.");
        Width = width;
        Height = height;
        CellSize = cellSize;
        Origin = origin;
        _flags = flags.ToArray();
        for (var i = 0; i < obstacleFlags.Length; i++)
            _flags[i] |= obstacleFlags[i];
    }

    public bool Contains(GridCell cell) => cell.X >= 0 && cell.Y >= 0 && cell.X < Width && cell.Y < Height;

    public bool TryWorldToCell(SimVector2 position, out GridCell cell)
    {
        cell = default;
        var x = Math.Floor((position.X - Origin.X) / CellSize);
        var y = Math.Floor((position.Y - Origin.Y) / CellSize);
        if (!double.IsFinite(x) || !double.IsFinite(y) || x < 0 || y < 0 || x >= Width || y >= Height)
            return false;
        cell = new GridCell((int)x, (int)y);
        return true;
    }

    public byte FlagsAt(GridCell cell) => Contains(cell)
        ? _flags[cell.Y * Width + cell.X] : throw new ArgumentOutOfRangeException(nameof(cell));

    public bool IsWalkable(GridCell cell) => Contains(cell) && (FlagsAt(cell) & 0x02) == 0;
}

public sealed class TerrainHeights
{
    private readonly double[] _heights;
    public int Width { get; }
    public int Height { get; }
    public double TileSize { get; }
    public SimVector2 Origin { get; }

    public TerrainHeights(int width, int height, double tileSize, SimVector2 origin, ReadOnlySpan<double> heights)
    {
        TerrainValidation.Grid(width, height, tileSize, origin);
        if (width < 2 || height < 2 || heights.Length != checked(width * height))
            throw new ArgumentException("Height field requires at least 2x2 vertices and exact buffer length.");
        foreach (var value in heights)
            if (!double.IsFinite(value)) throw new ArgumentException("Height values must be finite.");
        Width = width;
        Height = height;
        TileSize = tileSize;
        Origin = origin;
        _heights = heights.ToArray();
    }

    public bool TrySample(SimVector2 position, out double height)
    {
        height = 0;
        var x = (position.X - Origin.X) / TileSize;
        var y = (position.Y - Origin.Y) / TileSize;
        if (!double.IsFinite(x) || !double.IsFinite(y) || x < 0 || y < 0 || x > Width - 1 || y > Height - 1)
            return false;
        // The last vertex belongs to the final quad, never the next row.
        var ix = Math.Min((int)Math.Floor(x), Width - 2);
        var iy = Math.Min((int)Math.Floor(y), Height - 2);
        var fx = x - ix;
        var fy = y - iy;
        var index = iy * Width + ix;
        height = _heights[index] * (1 - fx) * (1 - fy)
            + _heights[index + 1] * fx * (1 - fy)
            + _heights[index + Width] * (1 - fx) * fy
            + _heights[index + Width + 1] * fx * fy;
        return true;
    }
}

internal static class TerrainValidation
{
    internal static void Grid(int width, int height, double spacing, SimVector2 origin)
    {
        if (width <= 0 || height <= 0 || !double.IsFinite(spacing) || spacing <= 0
            || !double.IsFinite(origin.X) || !double.IsFinite(origin.Y))
            throw new ArgumentException("Invalid grid dimensions, spacing or origin.");
        _ = checked(width * height);
    }
}
