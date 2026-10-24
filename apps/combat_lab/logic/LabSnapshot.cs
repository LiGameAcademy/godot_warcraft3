using System.Text.Json.Serialization;
using Rts.Kernel;
using Rts.Kernel.Combat;
using Rts.Kernel.Numerics;

namespace Rts.CombatLab;

internal sealed record LabSnapshot(
    [property: JsonRequired] int Version,
    [property: JsonRequired] int TickRate,
    [property: JsonRequired] string Preset,
    [property: JsonRequired] string ContentHash,
    [property: JsonRequired] string Combat,
    [property: JsonRequired] LabEntity[] Entities,
    [property: JsonRequired] LabPending[] Pending,
    [property: JsonRequired] long NextSequence,
    [property: JsonRequired] long NextArrival);

internal sealed record LabEntity(
    [property: JsonRequired] ulong Id, [property: JsonRequired] int Owner,
    [property: JsonRequired] long X, [property: JsonRequired] long Y)
{
    internal static LabEntity From(EntityState entity) => new(entity.Id.Value, entity.OwnerId, entity.Position.X.Raw, entity.Position.Y.Raw);
    internal EntityState ToEntity() => new(new(Id), Owner, FixedVector2.FromRaw(X, Y), FixedVector2.Zero);
}

internal sealed record LabPending(
    [property: JsonRequired] long Frame, [property: JsonRequired] long Arrival,
    [property: JsonRequired] int Player, [property: JsonRequired] long Sequence,
    [property: JsonRequired] CombatCommandKind Kind, [property: JsonRequired] ulong Attacker,
    [property: JsonRequired] ulong Target)
{
    internal CombatCommand ToCommand() => new(Player, Sequence, Kind, new(Attacker), new(Target));
}
