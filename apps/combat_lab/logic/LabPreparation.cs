using System.Diagnostics;
using Rts.Kernel;
using Rts.Kernel.Combat;
using Rts.Kernel.Numerics;

namespace Rts.CombatLab;

internal sealed record LabPreparationResult(double ElapsedMs, long AllocatedBytes);

/// <summary>Loading-only first-call work in private fixtures. Never receives the caller's world.</summary>
internal static class LabPreparation
{
    private static readonly Lazy<LabPreparationResult> Ready = new(Initialize);

    internal static LabPreparationResult EnsureReady() => Ready.Value;

    private static LabPreparationResult Initialize()
    {
        var started = Stopwatch.GetTimestamp();
        var bytes = GC.GetAllocatedBytesForCurrentThread();
        Run(lethal: false);
        Run(lethal: true);
        return new(Stopwatch.GetElapsedTime(started).TotalMilliseconds,
            GC.GetAllocatedBytesForCurrentThread() - bytes);
    }

    private static void Run(bool lethal)
    {
        var definition = new CombatDefinition(lethal ? 12 : 60, 0, ArmorType.Light,
            new(lethal ? 12 : 10, lethal ? 0 : 1, 6, AttackType.Normal, 0, 90, lethal ? 0 : 2, 4));
        EntityState[] entities =
        [
            new(new(1), 0, new(0, 0), FixedVector2.Zero),
            new(new(2), 1, new(32, 0), FixedVector2.Zero),
            new(new(3), 1, new(64, 0), FixedVector2.Zero)
        ];
        var configuration = new LabConfiguration("loading-only", "Isolated loading fixture", 7, entities,
            entities.Select(entity => new CombatDefinitionEntry(entity.Id.Value, definition)).ToArray(),
            [new(1, 2), new(2, 1)]);
        var session = new LabSession(configuration);
        session.StartDuels();
        session.Step();
        session = LabSession.Load(session.Save(), [session.Configuration]);
        for (var frame = 2; frame <= 40; frame++)
        {
            if (!lethal)
            {
                if (frame == 2) { session.Stop(1); session.Attack(1, 3); }
                if (frame == 3) session.Attack(1, 3);
                if (frame == 5) session.Attack(1, 2);
                if (frame == 6) session.Stop(1);
                if (frame == 7) session.Attack(1, 2);
            }
            session.Step();
        }
    }
}
