using Rts.Kernel;
using Rts.Kernel.Combat;
using Rts.Kernel.Numerics;

namespace Rts.CombatLab;

internal sealed record LabDuel(ulong Attacker, ulong Target);
internal sealed record LabConfiguration(
    string Id, string Title, ulong Seed, IReadOnlyList<EntityState> Entities,
    IReadOnlyList<CombatDefinitionEntry> Definitions, IReadOnlyList<LabDuel> Duels)
{
    internal LabConfiguration Freeze()
    {
        if (string.IsNullOrWhiteSpace(Id) || string.IsNullOrWhiteSpace(Title))
            throw new ArgumentException("Preset identity and title are required.");
        var entities = Entities.OrderBy(entity => entity.Id).ToArray();
        var definitions = Definitions.OrderBy(entry => entry.Id).ToArray();
        if (entities.Length == 0 || entities.Length != definitions.Length
            || entities.Any(entity => entity.Id.IsNone || entity.OwnerId < 0 || entity.Velocity != FixedVector2.Zero
                || !SimulationDomain.Contains(entity.Position))
            || entities.Select(entity => entity.Id.Value).Distinct().Count() != entities.Length
            || !entities.Select(entity => entity.Id.Value).SequenceEqual(definitions.Select(entry => entry.Id)))
            throw new ArgumentException("Invalid stationary entity/definition set.");
        foreach (var entry in definitions) entry.Definition.Validate();
        var ids = entities.Select(entity => entity.Id.Value).ToHashSet();
        if (Duels.Any(duel => duel.Attacker == duel.Target || !ids.Contains(duel.Attacker) || !ids.Contains(duel.Target)))
            throw new ArgumentException("Invalid scripted duel command.");
        return this with
        {
            Entities = Array.AsReadOnly(entities),
            Definitions = Array.AsReadOnly(definitions),
            Duels = Array.AsReadOnly(Duels.ToArray())
        };
    }

    internal string ContentHash() => LabJson.Digest(LabJson.Write(new
    {
        Id, Seed, TickRate = LabSession.TickRate,
        Entities = Entities.Select(LabEntity.From).ToArray(), Definitions, Duels
    }));
}
