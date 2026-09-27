using Rts.Kernel;

var checks = 0;

void Check(bool condition, string message)
{
    checks++;
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

void CheckThrows<TException>(Action action, string message) where TException : Exception
{
    checks++;
    try
    {
        action();
    }
    catch (TException)
    {
        return;
    }

    throw new InvalidOperationException(message);
}

RtsMatch CreateMovingMatch()
{
    var match = new RtsMatch(MatchConfig.Default, 1234);
    Check(match.SubmitCommand(CommandEnvelope.Spawn(1, 1, 0, new SimVector2(10, 20))).Accepted, "spawn accepted");
    match.Step();
    var id = match.Entities.Single().Id;
    Check(match.SubmitCommand(CommandEnvelope.SetVelocity(2, 1, 1, id, new SimVector2(30, -15))).Accepted, "velocity accepted");
    match.Step();
    return match;
}

var original = CreateMovingMatch();
var moving = original.Entities.Single();
Check(moving.Id.Value == 1, "entity ids start at one");
Check(moving.Position == new SimVector2(11, 19.5), "fixed tick movement");
Check(!original.SubmitCommand(CommandEnvelope.Spawn(original.Frame, 1, 2, SimVector2.Zero)).Accepted, "past command rejected");
Check(original.SubmitCommand(CommandEnvelope.Stop(10, 1, 3, moving.Id)).Accepted, "future command accepted");

var snapshotJson = SnapshotJson.Serialize(original.CaptureSnapshot());
var restored = RtsMatch.Restore(SnapshotJson.Deserialize(snapshotJson));
Check(original.ComputeStateHash() == restored.ComputeStateHash(), "snapshot round trip hash");
Check(original.Rng.NextUInt64() == restored.Rng.NextUInt64(), "random state restored");
var canonicalSnapshot = original.CaptureSnapshot();
Check(SnapshotDiff.FindFirst(canonicalSnapshot, canonicalSnapshot) is null, "identical snapshots have no diff");
Check(SnapshotDiff.FindFirst(canonicalSnapshot, canonicalSnapshot with { Frame = canonicalSnapshot.Frame + 1 })?.Path == "frame", "frame diff path");
var changedEntities = canonicalSnapshot.Entities.ToArray();
changedEntities[0] = changedEntities[0] with { PositionX = changedEntities[0].PositionX + 1 };
Check(SnapshotDiff.FindFirst(canonicalSnapshot, canonicalSnapshot with { Entities = changedEntities })?.Path == "entities[0].positionX", "entity field diff path");
var changedPending = canonicalSnapshot.PendingCommands.ToArray();
changedPending[0] = changedPending[0] with
{
    Command = changedPending[0].Command with { ExecuteFrame = changedPending[0].Command.ExecuteFrame + 1 },
};
Check(SnapshotDiff.FindFirst(canonicalSnapshot, canonicalSnapshot with { PendingCommands = changedPending })?.Path == "pendingCommands[0].executeFrame", "command field diff path");
CheckThrows<InvalidDataException>(
    () => RtsMatch.Restore(canonicalSnapshot with { NextEntityId = 1 }),
    "non-canonical next entity id rejected");

for (var i = 0; i < 20; i++)
{
    original.Step();
    restored.Step();
    Check(original.ComputeStateHash() == restored.ComputeStateHash(), $"restored state at step {i}");
}

var left = CreateMovingMatch();
var right = CreateMovingMatch();
left.Step();
left.Step();
right.Step();
Check(left.Frame == right.Frame + 1, "matches keep independent clocks");
Check(left.ComputeStateHash() != right.ComputeStateHash(), "matches keep independent state");
right.Step();
Check(left.ComputeStateHash() == right.ComputeStateHash(), "same inputs converge after interleaved stepping");

var rejected = new RtsMatch(MatchConfig.Default, 99);
rejected.SubmitCommand(CommandEnvelope.SetVelocity(1, 4, 0, new EntityId(999), new SimVector2(1, 1)));
rejected.Step();
var rejectionEvent = rejected.DrainEvents().Single();
Check(rejectionEvent.Kind == MatchEventKind.CommandRejected, "execution rejection is an event");
Check(rejectionEvent.Frame == 1, "event carries simulation frame");

Console.WriteLine($"Rts.Kernel.Tests PASS ({checks} checks)");
