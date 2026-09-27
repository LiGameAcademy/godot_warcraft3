using Rts.Kernel;

var match = new RtsMatch(MatchConfig.Default, seed: 0xC0FFEEUL);
match.SubmitCommand(CommandEnvelope.Spawn(1, playerId: 0, sequence: 0, new SimVector2(128, 256)));
match.Step();

var entityId = match.Entities.Single().Id;
match.SubmitCommand(CommandEnvelope.SetVelocity(2, playerId: 0, sequence: 1, entityId, new SimVector2(30, 0)));
for (var i = 0; i < 30; i++)
{
    match.Step();
}

var entity = match.Entities.Single();
Console.WriteLine($"frame={match.Frame} entity={entity.Id} position=({entity.Position.X:F3},{entity.Position.Y:F3}) hash={match.ComputeStateHash()}");
