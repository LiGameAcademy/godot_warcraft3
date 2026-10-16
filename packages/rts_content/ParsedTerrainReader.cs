using System.Text.Json;
using Rts.Kernel.Numerics;
using Rts.Kernel.Navigation;

namespace Rts.Content;

/// <summary>Converts existing map-parse output without filesystem or Godot dependencies.</summary>
public static class ParsedTerrainReader
{
    public static PathingGrid ReadPathing(string json, ReadOnlySpan<byte> obstacleFlags = default)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var flags = root.TryGetProperty("cellsBase64", out var encoded) && !string.IsNullOrEmpty(encoded.GetString())
            ? Convert.FromBase64String(encoded.GetString()!)
            : root.GetProperty("cells").EnumerateArray().Select(value => value.GetByte()).ToArray();
        return new PathingGrid(root.GetProperty("width").GetInt32(), root.GetProperty("height").GetInt32(),
            JsonScalarInput.NumberOr(root, "cellSize", 32), Origin(root, "origin"), flags, obstacleFlags);
    }

    public static TerrainHeights ReadHeights(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        return new TerrainHeights(root.GetProperty("tilepointWidth").GetInt32(),
            root.GetProperty("tilepointHeight").GetInt32(), JsonScalarInput.NumberOr(root, "tileSize", 128),
            Origin(root, "centerOffset"),
            root.GetProperty("heights").EnumerateArray().Select(value => JsonScalarInput.Number(value)).ToArray());
    }

    private static FixedVector2 Origin(JsonElement root, string key) => root.TryGetProperty(key, out var value)
        ? new FixedVector2(JsonScalarInput.NumberOr(value, "x", 0), JsonScalarInput.NumberOr(value, "y", 0)) : FixedVector2.Zero;

}
