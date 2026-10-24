namespace Rts.CombatLab;

/// <summary>Only this laboratory's user-data save; failed reads never replace the current session.</summary>
internal sealed class LabSaveStore(string path)
{
    internal void Save(string json)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, json, new System.Text.UTF8Encoding(false));
        File.Move(temporary, path, overwrite: true);
    }
    internal string Load() => File.ReadAllText(path);
}
