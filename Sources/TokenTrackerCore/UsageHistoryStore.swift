import Foundation

public struct UsageHistoryEntry: Codable, Equatable, Sendable {
    public let recordedAt: Date
    public let snapshot: UsageSnapshot

    public init(recordedAt: Date, snapshot: UsageSnapshot) {
        self.recordedAt = recordedAt
        self.snapshot = snapshot
    }
}

public final class UsageHistoryStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        self.url = AppPaths.usageHistory
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> [UsageHistoryEntry] {
        guard
            let data = try? Data(contentsOf: url),
            let entries = try? decoder.decode([UsageHistoryEntry].self, from: data)
        else {
            return []
        }
        return entries.sorted { $0.recordedAt < $1.recordedAt }
    }

    public func append(_ snapshot: UsageSnapshot, retentionDays: Int, now: Date = Date()) {
        var entries = load()
        let newEntry = UsageHistoryEntry(recordedAt: now, snapshot: snapshot)

        if let last = entries.last, now.timeIntervalSince(last.recordedAt) < 60 {
            entries[entries.count - 1] = newEntry
        } else {
            entries.append(newEntry)
        }

        let cutoff = now.addingTimeInterval(-TimeInterval(max(1, retentionDays)) * 24 * 60 * 60)
        entries = entries.filter { $0.recordedAt >= cutoff }
        save(entries)
    }

    public func csvString() -> String {
        UsageHistoryFormatter.csvString(for: load())
    }

    private func save(_ entries: [UsageHistoryEntry]) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(entries)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
        }
    }
}

public enum UsageHistoryFormatter {
    public static func trendSummary(
        entries: [UsageHistoryEntry],
        current snapshot: UsageSnapshot,
        window: TimeInterval = 24 * 60 * 60,
        localizer: Localizer = Localizer(language: .english)
    ) -> String {
        let cutoff = snapshot.updatedAt.addingTimeInterval(-window)
        guard let baseline = entries.first(where: { $0.recordedAt >= cutoff }) else {
            return localizer.text(.notEnoughHistory)
        }

        return [
            localizer.text(.historyTrend),
            providerTrend(.claude, baseline: baseline.snapshot, current: snapshot),
            providerTrend(.codex, baseline: baseline.snapshot, current: snapshot)
        ].joined(separator: " ")
    }

    public static func csvString(for entries: [UsageHistoryEntry]) -> String {
        let header = [
            "recorded_at",
            "provider",
            "remaining_5h",
            "remaining_7d",
            "reset_5h",
            "reset_7d",
            "source",
            "plan",
            "error"
        ].joined(separator: ",")

        let rows = entries.flatMap { entry in
            [entry.snapshot.claude, entry.snapshot.codex].map { usage in
                [
                    isoString(entry.recordedAt),
                    usage.provider.rawValue,
                    optionalInt(usage.remainingPercent5h),
                    optionalInt(usage.remainingPercent7d),
                    optionalDate(usage.resetAt5h),
                    optionalDate(usage.resetAt7d),
                    usage.source.rawValue,
                    usage.plan ?? "",
                    usage.error ?? ""
                ].map(csvEscape).joined(separator: ",")
            }
        }

        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func providerTrend(_ provider: Provider, baseline: UsageSnapshot, current: UsageSnapshot) -> String {
        let previous = baseline.usage(for: provider).remainingPercent5h
        let latest = current.usage(for: provider).remainingPercent5h
        guard let previous, let latest else {
            return "\(provider.displayName) 5h --"
        }
        let delta = latest - previous
        if delta > 0 {
            return "\(provider.displayName) 5h +\(delta)%"
        }
        return "\(provider.displayName) 5h \(delta)%"
    }

    private static func optionalInt(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func optionalDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return isoString(date)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
