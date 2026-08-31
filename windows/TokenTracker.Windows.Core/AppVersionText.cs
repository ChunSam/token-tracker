namespace TokenTracker.Windows.Core;

/// <summary>
/// How the tray app names the build it is running.
///
/// The assembly version was never set, so diagnostics reported `1.0.0` for every
/// build ever shipped — the one line that has to be trusted about which build a
/// report came from. Release publishes now stamp the tag into the version and the
/// CI run number into the revision field, which is the Windows counterpart to the
/// macOS bundle's build number.
/// </summary>
public static class AppVersionText
{
    /// <summary>
    /// `1.1.6 (build 8)` for a release publish, `1.1.6` for a local build whose
    /// revision nobody stamped. Mirrors the macOS `1.1.6 (8)` line.
    /// </summary>
    public static string Format(Version? version) =>
        version is null
            ? "unknown"
            : version.Revision > 0
                ? $"{version.Major}.{version.Minor}.{version.Build} (build {version.Revision})"
                : $"{version.Major}.{version.Minor}.{version.Build}";
}
