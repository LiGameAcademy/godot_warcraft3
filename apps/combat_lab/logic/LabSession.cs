using Rts.Kernel;
using Rts.Kernel.Combat;

namespace Rts.CombatLab;

/// <summary>Independent test-host state: fixed entities and future inputs; combat owns health and rules.</summary>
internal sealed class LabSession
{
    internal const int TickRate = 30;
    internal LabConfiguration Configuration { get; }
    private readonly StationaryCombat _combat;
    private readonly List<LabPending> _pending = [];
    private readonly Dictionary<ulong, EntityState> _entities;
    private long _nextSequence;
    private long _nextArrival;

    internal LabSession(LabConfiguration configuration)
    {
        Configuration = configuration.Freeze();
        _entities = Configuration.Entities.ToDictionary(entity => entity.Id.Value);
        _combat = new(Configuration.Seed);
        foreach (var entry in Configuration.Definitions) _combat.AddCombatant(new(entry.Id), entry.Definition);
    }

    private LabSession(LabConfiguration configuration, StationaryCombat combat)
    {
        Configuration = configuration;
        _entities = configuration.Entities.ToDictionary(entity => entity.Id.Value);
        _combat = combat;
    }

    internal long Frame => _combat.Frame;
    internal IReadOnlyList<CombatantState> ReadStates() => _combat.ReadCombatants();
    internal string CombatHash() => _combat.ComputeStateHash();
    internal string StateHash() => LabJson.Digest(Save());

    internal void Attack(ulong attacker, ulong target) => Queue(CombatCommandKind.Attack, attacker, target);
    internal void Stop(ulong attacker) => Queue(CombatCommandKind.Stop, attacker, 0);
    internal void StartDuels()
    {
        foreach (var duel in Configuration.Duels) Attack(duel.Attacker, duel.Target);
    }

    private void Queue(CombatCommandKind kind, ulong attacker, ulong target)
    {
        if (!_entities.TryGetValue(attacker, out var entity)) throw new ArgumentException("Unknown selected entity.");
        if (Frame >= long.MaxValue - CombatTiming.MaxFrames) throw new InvalidOperationException("Logical frame limit reached.");
        var sequence = checked(_nextSequence + 1);
        var arrival = checked(_nextArrival + 1);
        _pending.Add(new(Frame + 1, _nextArrival, entity.OwnerId, _nextSequence, kind, attacker, target));
        _nextSequence = sequence;
        _nextArrival = arrival;
    }

    internal CombatStepResult Step()
    {
        var due = _pending.Where(command => command.Frame == Frame + 1).OrderBy(command => command.Arrival).ToArray();
        var result = _combat.Advance(Frame + 1, Configuration.Entities, due.Select(command => command.ToCommand()).ToArray());
        _pending.RemoveAll(command => command.Frame <= Frame);
        return result;
    }

    internal string Save() => LabJson.Write(new LabSnapshot(
        1, TickRate, Configuration.Id, Configuration.ContentHash(), CombatSnapshotJson.Serialize(_combat.CaptureSnapshot()),
        Configuration.Entities.Select(LabEntity.From).ToArray(),
        _pending.OrderBy(command => command.Frame).ThenBy(command => command.Arrival).ToArray(), _nextSequence, _nextArrival));

    internal static LabSession Load(string json, IReadOnlyList<LabConfiguration> configurations)
    {
        var saved = LabJson.Read<LabSnapshot>(json);
        var configuration = configurations.SingleOrDefault(candidate => candidate.Id == saved.Preset)?.Freeze()
            ?? throw new InvalidDataException("Unknown combat laboratory preset.");
        if (saved.Version != 1 || saved.TickRate != TickRate || saved.ContentHash != configuration.ContentHash() || saved.Combat is null
            || saved.Entities is null || saved.Pending is null || saved.NextSequence < 0 || saved.NextArrival < 0
            || !saved.Entities.SequenceEqual(configuration.Entities.Select(LabEntity.From)))
            throw new InvalidDataException("Laboratory configuration, entities or clock mismatch.");
        var combat = StationaryCombat.Restore(CombatSnapshotJson.Deserialize(saved.Combat), configuration.Definitions);
        ValidatePending(saved, combat.Frame, configuration);
        var session = new LabSession(configuration, combat) { _nextSequence = saved.NextSequence, _nextArrival = saved.NextArrival };
        session._pending.AddRange(saved.Pending);
        return session;
    }

    private static void ValidatePending(LabSnapshot saved, long frame, LabConfiguration configuration)
    {
        var arrivals = new HashSet<long>();
        var sequences = new HashSet<long>();
        foreach (var command in saved.Pending)
        {
            if (command is null || command.Frame != frame + 1 || command.Frame > long.MaxValue - CombatTiming.MaxFrames
                || command.Arrival < 0 || command.Arrival >= saved.NextArrival || !arrivals.Add(command.Arrival)
                || command.Sequence < 0 || command.Sequence >= saved.NextSequence || !sequences.Add(command.Sequence)
                || !configuration.Entities.Any(entity => entity.Id.Value == command.Attacker && entity.OwnerId == command.Player)
                || !Enum.IsDefined(command.Kind)
                || (command.Kind == CombatCommandKind.Stop ? command.Target != 0 : command.Target == 0))
                throw new InvalidDataException("Invalid pending laboratory command.");
        }
    }
}
