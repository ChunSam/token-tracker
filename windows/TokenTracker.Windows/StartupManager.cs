using Microsoft.Win32;
using System.Windows.Forms;

namespace TokenTracker.Windows;

internal static class StartupManager
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Token Tracker";

    public static bool IsEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
        return string.Equals(key?.GetValue(ValueName) as string, Application.ExecutablePath, StringComparison.OrdinalIgnoreCase);
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true)
            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath, true);

        if (enabled)
        {
            key.SetValue(ValueName, Application.ExecutablePath);
        }
        else
        {
            key.DeleteValue(ValueName, false);
        }
    }
}
