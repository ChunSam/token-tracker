import Foundation

/// Whether a newer release is out. The app has no signed auto-update path and is
/// installed by hand from GitHub Releases, so the most it can do is say a new
/// version exists and link to the page that has it.
public enum UpdateCheck {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/ChunSam/tokki/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/ChunSam/tokki/releases/latest")!

    /// Once a day is plenty for releases cut by hand, and far inside GitHub's 60
    /// unauthenticated requests an hour.
    public static let interval: TimeInterval = 24 * 3600
    /// After a failed check — offline at launch, say — try again within the hour
    /// rather than waiting out the day.
    public static let retryInterval: TimeInterval = 3600

    /// The version a `releases/latest` response names, without its leading `v`.
    /// Drafts, prereleases and tags that are not plain dotted numbers are nil, so
    /// a `-beta` tag never reads as newer than the build it would replace.
    public static func latestVersion(fromReleaseJSON json: Any) -> String? {
        guard let object = json as? [String: Any],
              object["draft"] as? Bool != true,
              object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String,
              components(tag) != nil else {
            return nil
        }
        return normalized(tag)
    }

    /// Compared number by number, so 1.1.10 is newer than 1.1.9. A version either
    /// side cannot read is never newer: an unknown build should not nag.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = components(candidate), let old = components(current) else {
            return false
        }
        for index in 0..<max(new.count, old.count) {
            let lhs = index < new.count ? new[index] : 0
            let rhs = index < old.count ? old[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }
        return false
    }

    public static func nextCheck(after attemptAt: Date, succeeded: Bool) -> Date {
        attemptAt.addingTimeInterval(succeeded ? interval : retryInterval)
    }

    /// `nil` means no check has been tried yet, which is due at once.
    public static func isDue(nextCheckAt: Date?, now: Date) -> Bool {
        guard let nextCheckAt else { return true }
        return now >= nextCheckAt
    }

    /// The latest release's version, or nil for any failure. A missed check is
    /// retried later and is never worth an error on screen.
    public static func fetchLatestVersion() async -> String? {
        do {
            let json = try await HTTPClient().getJSON(
                url: latestReleaseAPI,
                headers: ["Accept": "application/vnd.github+json", "User-Agent": "Tokki"],
                timeout: 10,
                serviceName: "GitHub"
            )
            return latestVersion(fromReleaseJSON: json)
        } catch {
            return nil
        }
    }

    private static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = normalized(version).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }
}
