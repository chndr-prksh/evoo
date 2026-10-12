using System;
using System.IO;
using System.Text.Json;

namespace Evoo.Windows;

/// <summary>The few choices Evoo remembers, in %LOCALAPPDATA%\Evoo\settings.json.</summary>
internal sealed class Settings
{
    public bool VoiceCommands { get; set; } = true;
    public bool Polish { get; set; } = true;

    private static string File_ => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Evoo", "settings.json");

    public static Settings Current { get; } = Load();

    private static Settings Load()
    {
        try { return JsonSerializer.Deserialize<Settings>(File.ReadAllText(File_)) ?? new Settings(); }
        catch { return new Settings(); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(File_)!);
            File.WriteAllText(File_, JsonSerializer.Serialize(this));
        }
        catch { /* settings are a convenience; never fail on them */ }
    }
}
