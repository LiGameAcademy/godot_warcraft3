var checks = 0;
void Check(bool condition, string message)
{
    checks++;
    if (!condition) throw new InvalidOperationException(message);
}
if (args.Length == 2 && args[0] == "--profile") LabHostChecks.Profile(Check, int.Parse(args[1]));
else LabHostChecks.Run(Check);
Console.WriteLine($"COMBAT_LAB_CLI_PASS checks={checks}");
