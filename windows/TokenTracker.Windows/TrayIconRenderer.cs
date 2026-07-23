using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

internal static class TrayIconRenderer
{
    private static readonly Color NormalBackground = Color.FromArgb(26, 126, 188);
    private static readonly Color WarningBackground = Color.FromArgb(255, 138, 143);

    public static Icon Render(UsageSnapshot? snapshot, DisplayMode mode)
    {
        var value = DisplayFormatter.TrayIconPercent(snapshot, mode);
        var warning = DisplayFormatter.TrayIconShowsWarning(snapshot, mode);
        var text = value is null ? "--" : value.Value.ToString();

        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
        graphics.Clear(Color.Transparent);

        using var background = new SolidBrush(warning ? WarningBackground : NormalBackground);
        graphics.FillEllipse(background, 0, 0, 31, 31);

        var fontSize = text.Length switch
        {
            <= 1 => 17f,
            2 => 14f,
            _ => 10f
        };

        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var foreground = new SolidBrush(Color.White);
        var textSize = graphics.MeasureString(text, font);
        graphics.DrawString(text, font, foreground, (32 - textSize.Width) / 2, (32 - textSize.Height) / 2 - 1);

        var handle = bitmap.GetHicon();
        try
        {
            return (Icon)Icon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
