using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Rts.CombatLab;

internal static class LabJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 32
    };
    internal static string Write<T>(T value) => JsonSerializer.Serialize(value, Options);
    internal static string Digest(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    internal static T Read<T>(string json)
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 32 });
        RejectDuplicateNames(document.RootElement);
        return JsonSerializer.Deserialize<T>(json, Options) ?? throw new InvalidDataException("Missing laboratory save.");
    }

    private static void RejectDuplicateNames(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new JsonException($"Duplicate property: {property.Name}.");
                RejectDuplicateNames(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var item in element.EnumerateArray()) RejectDuplicateNames(item);
    }
}
