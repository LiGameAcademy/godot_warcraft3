using System;
using System.ComponentModel;
using System.Diagnostics;
using Godot;

/// <summary>Queries unrelated processes; Godot on Windows only tracks its own children.</summary>
public partial class AssetProcessProbe : RefCounted
{
    public bool IsRunning(int pid, string birth = "")
    {
        if (pid <= 0) return true; // Unknown ownership must not allow cache deletion.
        try
        {
            using Process process = Process.GetProcessById(pid);
            if (process.HasExited) return false;
            return string.IsNullOrEmpty(birth) || birth == "unknown"
                || process.StartTime.ToUniversalTime().Ticks.ToString() == birth;
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (Win32Exception) { return true; } // Access denied: preserve the owner's cache.
    }
    public string Identity(int pid)
    {
        if (pid <= 0) return "";
        try
        {
            using Process process = Process.GetProcessById(pid);
            return process.StartTime.ToUniversalTime().Ticks.ToString();
        }
        catch (ArgumentException) { return ""; }
        catch (InvalidOperationException) { return ""; }
        catch (Win32Exception) { return "unknown"; }
    }
}
