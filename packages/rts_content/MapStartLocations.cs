using System.Text.Json;
using Rts.Kernel.Numerics;

namespace Rts.Content;

public sealed record MapStartLocation(int PlayerId, FixedVector2 Position);

/// <summary>Only sloc markers are interpreted; neutral/placed units are not converted into runtime actors.</summary>
public static class MapStartLocations
{
    public static IReadOnlyList<MapStartLocation> Read(string unitsJson)
    {
        using var document = JsonDocument.Parse(unitsJson);
        var starts = new SortedDictionary<int, MapStartLocation>();
        foreach (var unit in document.RootElement.GetProperty("units").EnumerateArray())
        {
            if (unit.GetProperty("typeId").GetString() != "sloc") continue;
            var player = unit.GetProperty("owner").GetInt32();
            var point = unit.GetProperty("position");
            var position = new FixedVector2(JsonScalarInput.Number(point.GetProperty("x")),
                JsonScalarInput.Number(point.GetProperty("y")));
            if (player is < 0 or > 9 || !SimulationDomain.Contains(position) || !starts.TryAdd(player, new(player, position)))
                throw new InvalidDataException("Start markers need unique players 0..9 and in-domain coordinates.");
        }
        return Array.AsReadOnly(starts.Values.ToArray());
    }
}
