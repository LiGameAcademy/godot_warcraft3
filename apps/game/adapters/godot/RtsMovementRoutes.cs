using Godot;
using Rts.Kernel;
using Rts.Kernel.Navigation;
using Rts.Kernel.Numerics;

internal static class RtsMovementRoutes
{
    internal static Godot.Collections.Array<Godot.Collections.Dictionary> Read(RtsMatch match,
        TerrainHeights? terrain, long[] selected)
    {
        var result = new Godot.Collections.Array<Godot.Collections.Dictionary>();
        if (selected.Length > 24) return result;
        Vector3 Point(FixedVector2 point)
        {
            var height = SimScalar.Zero;
            if (terrain is not null) terrain.TrySample(point, out height);
            return new((float)point.X.ToPresentationDouble(), (float)point.Y.ToPresentationDouble(),
                (float)height.ToPresentationDouble());
        }
        foreach (var route in match.ReadMovementRoutes(selected.Where(id => id > 0)
                     .Select(id => new EntityId((ulong)id)).ToArray()))
        {
            var view = new Godot.Collections.Dictionary
            {
                ["id"] = checked((long)route.EntityId.Value),
                ["points"] = route.Waypoints.Select(Point).ToArray(),
                ["temporary"] = route.TemporaryYield, ["settled"] = route.Settled,
                ["wait_frames"] = route.WaitFrames,
            };
            if (route.PreferredGoal is { } goal) view["preferred_goal"] = Point(goal);
            result.Add(view);
        }
        return result;
    }
}
