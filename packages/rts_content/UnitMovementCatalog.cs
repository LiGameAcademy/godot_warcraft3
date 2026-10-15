using System.Text.Json;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

namespace Rts.Content;

/// <summary>Frozen ground capabilities from the existing UnitData/UnitBalance records.</summary>
public sealed class UnitMovementCatalog
{
    private readonly Dictionary<string, MovementDefinition> _ground = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _excluded = new(StringComparer.Ordinal);
    public IReadOnlyList<MovementDefinition> Definitions { get; }
    public IReadOnlyList<string> GroundCodes { get; }
    public int ExcludedCount => _excluded.Count;

    public UnitMovementCatalog(string unitDataJson, string unitBalanceJson)
    {
        using var data = JsonDocument.Parse(unitDataJson);
        using var balance = JsonDocument.Parse(unitBalanceJson);
        var dataRows = Index(data.RootElement, "unitID");
        var balanceRows = Index(balance.RootElement, "unitBalanceID");
        foreach (var (code, row) in dataRows.OrderBy(item => item.Key, StringComparer.Ordinal))
        {
            if (!balanceRows.TryGetValue(code, out var numbers))
                throw new InvalidDataException($"UnitBalance is missing {code}.");
            var mode = row.GetProperty("movetp").GetString();
            if (mode is not ("foot" or "horse"))
            {
                _excluded.Add(code, $"unsupported_movement:{mode}");
                continue;
            }
            var speedToken = numbers.GetProperty("spd");
            // Existing SLK exports use '_' and '-' as explicit missing-value markers.
            if (speedToken.ValueKind == JsonValueKind.String && speedToken.GetString() is "_" or "-")
            {
                _excluded.Add(code, "no_movement_speed");
                continue;
            }
            var speed = JsonScalarInput.Number(speedToken);
            if (speed == 0)
            {
                _excluded.Add(code, "no_movement_speed");
                continue;
            }
            var radius = JsonScalarInput.Number(numbers.GetProperty("collision"));
            var turnRate = JsonScalarInput.Number(row.GetProperty("turnRate"));
            if (!SimulationDomain.IsCapability(speed) || !SimulationDomain.IsCapability(radius)
                || turnRate < SimScalar.FromRatio(1, 20) || turnRate > SimulationDomain.CapabilityLimit)
                throw new InvalidDataException($"Invalid ground movement capabilities for {code}.");
            // The current kernel contract is revolutions/second. Original WC3 units remain separate research.
            _ground.Add(code, new MovementDefinition(DefinitionId(code), speed, radius, new MotionParameters(TurnRate: turnRate)));
        }
        Definitions = Array.AsReadOnly(_ground.Values.OrderBy(item => item.Id).ToArray());
        GroundCodes = Array.AsReadOnly(_ground.Keys.Order(StringComparer.Ordinal).ToArray());
    }

    public bool TryGet(string code, out MovementDefinition? definition) => _ground.TryGetValue(code, out definition);
    public string? ExclusionReason(string code) => _excluded.GetValueOrDefault(code);

    /// <summary>Case-sensitive FourCC, big-endian ASCII; stable across table order and processes.</summary>
    public static ulong DefinitionId(string code)
    {
        if (code.Length != 4 || code.Any(character => character is < ' ' or > '~'))
            throw new InvalidDataException("Unit code must contain four printable ASCII characters.");
        return ((ulong)code[0] << 24) | ((ulong)code[1] << 16) | ((ulong)code[2] << 8) | code[3];
    }

    private static Dictionary<string, JsonElement> Index(JsonElement root, string identity)
    {
        var rows = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var row in root.GetProperty("records").EnumerateArray())
        {
            var code = row.GetProperty(identity).GetString()
                ?? throw new InvalidDataException($"Missing {identity}.");
            _ = DefinitionId(code);
            if (!rows.TryAdd(code, row)) throw new InvalidDataException($"Duplicate {identity}: {code}.");
        }
        return rows;
    }
}
