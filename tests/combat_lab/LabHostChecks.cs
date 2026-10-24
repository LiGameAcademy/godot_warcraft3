using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Rts.CombatLab;
using Rts.Kernel;
using Rts.Kernel.Combat;
using Rts.Kernel.Numerics;

internal static class LabHostChecks
{
    internal static LabConfiguration Pairs(int count, int health = 1000000, int windup = 18)
    {
        var profile = new CombatDefinition(health, 0, ArmorType.Light, new(10, 1, 6, AttackType.Normal, 0, 90, windup, 45));
        var entities = Enumerable.Range(0, count).Select(index =>
            new EntityState(new((ulong)index + 1), index % 2, new(index / 2 * 220 + index % 2 * 76, 0), FixedVector2.Zero)).ToArray();
        return new("pairs", "配对交战", 253, entities,
            entities.Select(entity => new CombatDefinitionEntry(entity.Id.Value, profile)).ToArray(),
            entities.Select(entity => new LabDuel(entity.Id.Value, ((entity.Id.Value - 1) ^ 1) + 1)).ToArray());
    }

    internal static void Run(Action<bool, string> check)
    {
        var configuration = Pairs(4);
        var session = new LabSession(configuration);
        session.Attack(1, 2);
        var before = session.Save();
        var clone = LabSession.Load(before, [configuration]);
        check(session.StateHash() == clone.StateHash(), "pending attack and input counters survive save before first step");
        for (var frame = 1; frame <= 100; frame++)
        {
            if (frame == 7) { session.Stop(1); clone.Stop(1); }
            if (frame == 8) { session.Attack(1, 2); clone.Attack(1, 2); }
            var a = session.Step();
            var b = clone.Step();
            check(a.Events.SequenceEqual(b.Events) && session.StateHash() == clone.StateHash(), "session JSON resumes controls and event identities");
        }
        check(LabSession.Load(before, [configuration]).Frame == 0, "later execution does not mutate saved state");
        var saved = LabJson.Read<LabSnapshot>(before);
        void Bad(LabSnapshot bad)
        {
            try { LabSession.Load(LabJson.Write(bad), [configuration]); }
            catch (InvalidDataException) { check(true, "corrupt root save rejected"); return; }
            check(false, "invalid root save must reject");
        }
        Bad(saved with { TickRate = 60 });
        Bad(saved with { ContentHash = new string('0', 64) });
        Bad(saved with { NextSequence = 0 });
        Bad(saved with { NextArrival = 0 });
        Bad(saved with { Pending = [saved.Pending[0], saved.Pending[0]] });
        Bad(saved with { Pending = [saved.Pending[0] with { Frame = 0 }] });
        Bad(saved with { Pending = [saved.Pending[0] with { Frame = 2 }] });
        Bad(saved with { Pending = [saved.Pending[0] with { Player = 1 }] });
        Bad(saved with { Pending = [saved.Pending[0] with { Attacker = 99 }] });
        Bad(saved with { Entities = saved.Entities.Reverse().ToArray() });
        Bad(saved with { Entities = [saved.Entities[0] with { X = 123 }, .. saved.Entities.Skip(1)] });
        check(session.Frame == 100, "failed loads cannot replace a running session");

        var duel = Pairs(2, health: 1, windup: 0);
        session = new LabSession(duel);
        session.StartDuels();
        var deaths = session.Step();
        check(deaths.Events.Count(e => e.Kind == CombatEventKind.UnitDied) == 2, "host submits both factions in same frame for mutual death");
        clone = LabSession.Load(session.Save(), [duel]);
        check(!clone.Step().Events.Any(), "host death restore emits no duplicate hits or deaths");

        configuration = Pairs(2);
        session = new LabSession(configuration);
        session.Attack(1, 2);
        session.Step();
        var firstDeadline = session.ReadStates()[0].NextAttackFrame;
        session.Stop(1);
        session.Attack(1, 2);
        session.Step();
        check(session.ReadStates()[0].NextAttackFrame == firstDeadline, "host Stop and reattack preserve cooldown");
    }

    internal static void Profile(Action<bool, string> check, int count)
    {
        var configuration = Pairs(count).Freeze();
        var host = new LabSession(configuration);
        var direct = new StationaryCombat(configuration.Seed);
        foreach (var entry in configuration.Definitions) direct.AddCombatant(new(entry.Id), entry.Definition);
        host.StartDuels();
        var commands = configuration.Duels.Select((duel, index) => new CombatCommand(
            configuration.Entities.Single(e => e.Id.Value == duel.Attacker).OwnerId, index,
            CombatCommandKind.Attack, new(duel.Attacker), new(duel.Target))).ToArray();
        using var state = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        using var events = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var samples = new double[600];
        for (var i = 0; i < samples.Length; i++)
        {
            var started = Stopwatch.GetTimestamp();
            var result = host.Step();
            samples[i] = Stopwatch.GetElapsedTime(started).TotalMilliseconds;
            var expected = direct.Advance(i + 1, configuration.Entities, i == 0 ? commands : []);
            check(host.CombatHash() == direct.ComputeStateHash() && result.Events.SequenceEqual(expected.Events), "host commands and frame results match direct CLI kernel");
            state.AppendData(Encoding.UTF8.GetBytes(host.StateHash()));
            events.AppendData(JsonSerializer.SerializeToUtf8Bytes(result.Events));
        }
        var sorted = samples.Order().ToArray();
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            scenario = "combat_lab_host", count, frames = samples.Length,
            first_ms = samples[0], max_ms = sorted[^1], p95_ms = sorted[569],
            over_budget = samples.Count(ms => ms > 1000.0 / 30),
            state_hash = Convert.ToHexString(state.GetHashAndReset()), event_hash = Convert.ToHexString(events.GetHashAndReset()),
            samples_ms = samples
        }));
    }
}
