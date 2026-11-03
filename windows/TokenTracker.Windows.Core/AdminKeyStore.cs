using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace TokenTracker.Windows.Core;

/// <summary>
/// Where an organization's Admin API key is kept. An Admin key can manage the
/// whole organization, so never a plain file: DPAPI here, the keychain on macOS.
/// Mirrors Sources/TokenTrackerCore/AdminKeyStore.swift.
/// </summary>
public interface IAdminKeyStore
{
    string? Key(Provider provider);

    bool Save(Provider provider, string key);

    void Delete(Provider provider);
}

public static class AdminKeyText
{
    /// <c>…ab12</c>: all of a key that settings and diagnostics may show. A key too
    /// short to be real shows nothing, so the four characters are never most of it.
    public static string Suffix(string key) => key.Length > 8 ? "…" + key[^4..] : "…";

    /// The file entry, or macOS keychain account, that holds this provider's Admin
    /// key. Named for the organization the key belongs to, not the CLI.
    internal static string Account(Provider provider) =>
        provider == Provider.Claude ? "anthropic-admin" : "openai-admin";
}

/// <summary>
/// Both keys in one file, encrypted with DPAPI for the signed-in Windows user, so
/// another account on the PC, or the file copied elsewhere, cannot read them.
/// </summary>
public sealed class DpapiAdminKeyStore : IAdminKeyStore
{
    // Ties the blob to this app: another program running as the same user has to
    // know this too.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Token Tracker admin keys");

    public string Path { get; }

    public DpapiAdminKeyStore(string? path = null)
    {
        Path = path ?? AppPaths.AdminKeysPath;
    }

    public string? Key(Provider provider) =>
        Read().TryGetValue(AdminKeyText.Account(provider), out var key) && key.Trim() is { Length: > 0 } trimmed
            ? trimmed
            : null;

    public bool Save(Provider provider, string key)
    {
        var keys = Read();
        keys[AdminKeyText.Account(provider)] = key.Trim();
        return Write(keys);
    }

    public void Delete(Provider provider)
    {
        var keys = Read();
        if (keys.Remove(AdminKeyText.Account(provider)))
        {
            Write(keys);
        }
    }

    private Dictionary<string, string> Read()
    {
        if (!OperatingSystem.IsWindows())
        {
            return new Dictionary<string, string>();
        }

        try
        {
            if (!File.Exists(Path))
            {
                return new Dictionary<string, string>();
            }

            var json = ProtectedData.Unprotect(File.ReadAllBytes(Path), Entropy, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new Dictionary<string, string>();
        }
        catch
        {
            return new Dictionary<string, string>();
        }
    }

    private bool Write(Dictionary<string, string> keys)
    {
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        try
        {
            if (keys.Count == 0)
            {
                File.Delete(Path);
                return true;
            }

            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var blob = ProtectedData.Protect(JsonSerializer.SerializeToUtf8Bytes(keys), Entropy, DataProtectionScope.CurrentUser);
            var tempPath = Path + ".tmp";
            File.WriteAllBytes(tempPath, blob);
            File.Move(tempPath, Path, overwrite: true);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
