using System.Drawing;
using System.Windows.Forms;
using TokenTracker.Windows.Core;

namespace TokenTracker.Windows;

/// <summary>
/// Asks for a provider's Admin key. The key file is read only here, when the user
/// opens this, and the key goes nowhere but into DPAPI.
/// </summary>
internal static class AdminKeyDialog
{
    /// True when a key was saved or deleted.
    public static bool Run(IWin32Window owner, Provider provider, IAdminKeyStore store, Localizer localizer)
    {
        var existing = store.Key(provider);
        var stored = existing is null
            ? localizer.Text(L10nKey.AdminKeyNone)
            : localizer.Text(L10nKey.AdminKeyStored).Replace("{suffix}", AdminKeyText.Suffix(existing), StringComparison.Ordinal);

        using var form = new Form
        {
            Text = localizer.Text(L10nKey.AdminKeyTitle)
                .Replace("{organization}", AdminKeyText.Organization(provider), StringComparison.Ordinal),
            FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false,
            MinimizeBox = false,
            ShowInTaskbar = false,
            StartPosition = FormStartPosition.CenterParent,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Padding = new Padding(12)
        };
        var layout = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true
        };
        layout.Controls.Add(new Label
        {
            Text = localizer.Text(L10nKey.AdminKeyGuidance),
            AutoSize = true,
            MaximumSize = new Size(360, 0)
        });
        layout.Controls.Add(new Label
        {
            Text = stored,
            AutoSize = true,
            Margin = new Padding(0, 8, 0, 4)
        });
        var input = new TextBox
        {
            Width = 360,
            UseSystemPasswordChar = true,
            PlaceholderText = AdminKeyText.Prefix(provider) + "…"
        };
        layout.Controls.Add(input);

        // Right to left: the first button added sits at the right edge.
        var buttons = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Margin = new Padding(0, 12, 0, 0)
        };
        var cancel = new Button { Text = localizer.Text(L10nKey.AdminKeyCancel), DialogResult = DialogResult.Cancel, AutoSize = true };
        var save = new Button { Text = localizer.Text(L10nKey.AdminKeySave), DialogResult = DialogResult.OK, AutoSize = true };
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(save);
        if (existing is not null)
        {
            buttons.Controls.Add(new Button { Text = localizer.Text(L10nKey.AdminKeyDelete), DialogResult = DialogResult.Abort, AutoSize = true });
        }

        layout.Controls.Add(buttons);
        form.Controls.Add(layout);
        form.AcceptButton = save;
        form.CancelButton = cancel;

        switch (form.ShowDialog(owner))
        {
            case DialogResult.OK:
                var key = input.Text.Trim();
                if (key.Length == 0)
                {
                    return false;
                }

                if (!AdminKeyText.LooksLikeAdminKey(key, provider))
                {
                    Fail(owner, localizer.Text(L10nKey.AdminKeyInvalid)
                        .Replace("{prefix}", AdminKeyText.Prefix(provider), StringComparison.Ordinal));
                    return false;
                }

                if (!store.Save(provider, key))
                {
                    Fail(owner, localizer.Text(L10nKey.AdminKeySaveFailed));
                    return false;
                }

                return true;
            case DialogResult.Abort:
                store.Delete(provider);
                return true;
            default:
                return false;
        }
    }

    private static void Fail(IWin32Window owner, string message) =>
        MessageBox.Show(owner, message, "Token Tracker", MessageBoxButtons.OK, MessageBoxIcon.Warning);
}
