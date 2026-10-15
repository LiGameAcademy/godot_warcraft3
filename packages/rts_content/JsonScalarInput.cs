using System.Text.Json;
using Rts.Kernel.Numerics;

namespace Rts.Content;

internal static class JsonScalarInput
{
    internal static SimScalar Number(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Number) throw new InvalidDataException("A numeric content token is required.");
        return SimScalar.Parse(value.GetRawText());
    }
    internal static SimScalar NumberOr(JsonElement root, string name, SimScalar fallback) =>
        root.TryGetProperty(name, out var value) ? Number(value) : fallback;
}
