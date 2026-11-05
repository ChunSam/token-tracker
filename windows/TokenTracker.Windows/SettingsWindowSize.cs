using System.Drawing;
using System.Text.Json;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

/// The settings window's size, kept between launches like the macOS window's.
/// The form is disposed on close, so nothing else carries it to the next opening.
internal static class SettingsWindowSize
{
    private sealed record Record(int Width, int Height);

    public static Size Load(Size fallback, Size minimum, Size workingArea)
    {
        var size = fallback;
        try
        {
            if (File.Exists(AppPaths.SettingsWindowPath)
                && JsonSerializer.Deserialize<Record>(File.ReadAllText(AppPaths.SettingsWindowPath)) is { } record)
            {
                size = new Size(record.Width, record.Height);
            }
        }
        catch
        {
        }

        // A size saved on a bigger screen still has to fit this one.
        return new Size(
            Math.Clamp(size.Width, minimum.Width, Math.Max(minimum.Width, workingArea.Width)),
            Math.Clamp(size.Height, minimum.Height, Math.Max(minimum.Height, workingArea.Height)));
    }

    public static void Save(Size size)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.AppDataDirectory);
            File.WriteAllText(AppPaths.SettingsWindowPath, JsonSerializer.Serialize(new Record(size.Width, size.Height)));
        }
        catch
        {
        }
    }
}
