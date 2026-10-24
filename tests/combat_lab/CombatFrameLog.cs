using System.Diagnostics;
using System.Text.Json;

internal sealed class CombatFrameLog(int frames)
{
    private readonly Entry[] _entries = new Entry[frames];
    private readonly record struct Entry(long Start, long End, long Bytes,
        FrameSpikeLog.Counters Before, FrameSpikeLog.Counters After);

    internal static FrameSpikeLog.Counters ReadCounters() => FrameSpikeLog.ReadCounters();

    internal void Record(int frame, long start, long end, long bytes,
        FrameSpikeLog.Counters before, FrameSpikeLog.Counters after) =>
        _entries[frame] = new(start, end, bytes, before, after);

    internal void Report(int count)
    {
        for (var i = 0; i < _entries.Length; i++)
        {
            var entry = _entries[i];
            var elapsed = Stopwatch.GetElapsedTime(entry.Start, entry.End).TotalMilliseconds;
            if (i != 0 && elapsed <= 1000.0 / 30) continue;
            var thread = ThreadWorkObservation.Between(entry.Before.ThreadWork, entry.After.ThreadWork);
            Console.WriteLine("combat_frame=" + JsonSerializer.Serialize(new
            {
                count, frame = i + 1, phase = i == 0 ? "first-command" : "combat",
                process_id = Environment.ProcessId, native_thread_id = thread?.ThreadId,
                qpc_start = entry.Start, qpc_end = entry.End, qpc_frequency = Stopwatch.Frequency,
                elapsed_ms = elapsed, alloc_bytes = entry.Bytes,
                jit_ms = (entry.After.JitTicks - entry.Before.JitTicks) / (double)TimeSpan.TicksPerMillisecond,
                gc_pause_ms = (entry.After.PauseTicks - entry.Before.PauseTicks) / (double)TimeSpan.TicksPerMillisecond,
                gc0 = entry.After.Gen0 - entry.Before.Gen0, gc1 = entry.After.Gen1 - entry.Before.Gen1,
                gc2 = entry.After.Gen2 - entry.Before.Gen2,
                thread_cpu_ms = thread?.CpuTicks / (double)TimeSpan.TicksPerMillisecond,
                cpu_cycles = thread?.Cycles, over_budget = elapsed > 1000.0 / 30
            }));
        }
    }
}
