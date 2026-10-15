using Godot;
using Rts.Kernel;
using Rts.Kernel.Navigation;

internal static class RtsMovementFrame
{
    internal static Godot.Collections.Dictionary Read(RtsMatch match, TerrainHeights? terrain)
    {
        var count = match.Entities.Count;
        var ids = new long[count];
        var definitions = new long[count];
        var owners = new int[count];
        var positions = new Vector3[count]; // WC3 x/y/z; presentation converts axes and world scale.
        var facing = new double[count];
        var radii = new double[count];
        var moving = new byte[count];
        var queued = new int[count];
        var index = 0;
        foreach (var entity in match.Entities)
        {
            if (terrain is null || !terrain.TrySample(entity.Position, out var height))
                throw new InvalidOperationException("Movement presentation requires a valid terrain height.");
            ids[index] = checked((long)entity.Id.Value);
            definitions[index] = checked((long)entity.MovementDefinitionId);
            owners[index] = entity.OwnerId;
            positions[index] = new Vector3((float)entity.Position.X.ToPresentationDouble(),
                (float)entity.Position.Y.ToPresentationDouble(), (float)height.ToPresentationDouble());
            facing[index] = entity.Facing.ToPresentationDouble();
            radii[index] = (match.ReadMovementDefinition(entity.Id)?.Radius
                ?? throw new InvalidOperationException("Movement view has no definition.")).ToPresentationDouble();
            moving[index] = match.IsMoving(entity.Id) ? (byte)1 : (byte)0;
            queued[index] = match.GetPendingOrderCount(entity.Id);
            index++;
        }
        return new Godot.Collections.Dictionary
        {
            ["frame"] = match.Frame, ["ids"] = ids, ["definitions"] = definitions, ["owners"] = owners,
            ["positions"] = positions, ["facing"] = facing, ["radii"] = radii, ["moving"] = moving, ["queued"] = queued,
        };
    }
}
