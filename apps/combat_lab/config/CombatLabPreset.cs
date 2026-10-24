using Godot;
using Rts.CombatLab;
using Rts.Kernel;
using Rts.Kernel.Combat;
using Rts.Kernel.Numerics;

[GlobalClass]
public partial class CombatLabPreset : Resource
{
    [Export] public string ScenarioId { get; set; } = "";
    [Export] public string Title { get; set; } = "";
    [Export] public long Seed { get; set; } = 253;
    [Export] public int Health { get; set; } = 130;
    [Export] public int Damage { get; set; } = 10;
    [Export] public int Dice { get; set; } = 1;
    [Export] public int Sides { get; set; } = 6;
    [Export] public int Range { get; set; } = 90;
    [Export] public int WindupFrames { get; set; } = 18;
    [Export] public int CooldownFrames { get; set; } = 45;
    [Export] public Godot.Collections.Array<Vector2I> Positions { get; set; } = new();
    [Export] public Godot.Collections.Array<int> Owners { get; set; } = new();
    [Export] public Godot.Collections.Array<Vector2I> Duels { get; set; } = new();

    internal LabConfiguration ToConfiguration()
    {
        if (Seed < 0 || Positions.Count != Owners.Count) throw new ArgumentException("Invalid preset input.");
        var profile = new CombatDefinition(Health, 0, ArmorType.Light,
            new(Damage, Dice, Sides, AttackType.Normal, 0, Range, WindupFrames, CooldownFrames));
        var entities = Positions.Select((point, index) =>
            new EntityState(new((ulong)index + 1), Owners[index], new(point.X, point.Y), FixedVector2.Zero)).ToArray();
        return new LabConfiguration(ScenarioId, Title, (ulong)Seed, entities,
            entities.Select(entity => new CombatDefinitionEntry(entity.Id.Value, profile)).ToArray(),
            Duels.Select(pair => new LabDuel(checked((ulong)pair.X), checked((ulong)pair.Y))).ToArray()).Freeze();
    }
}
