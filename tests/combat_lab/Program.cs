var checks = 0;
void Check(bool condition, string message)
{
    checks++;
    if (!condition) throw new InvalidOperationException(message);
}
if (args.Length == 3 && args[0] == "--save-profile")
{
    var session = new Rts.CombatLab.LabSession(LabHostChecks.Pairs(int.Parse(args[1])));
    session.StartDuels();
    session.Step();
    session.Stop(1);
    session.Attack(1, 2);
    File.WriteAllText(args[2], session.Save());
}
else if (args.Length >= 2 && args[0] == "--profile") LabHostChecks.Profile(Check, int.Parse(args[1]), args.Length > 2 ? args[2] : null);
else LabHostChecks.Run(Check);
Console.WriteLine($"COMBAT_LAB_CLI_PASS checks={checks}");
