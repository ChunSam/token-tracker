import Foundation

struct CodexLogReader {
    func latestUsage() -> ProviderUsage? {
        let files = rolloutFiles()
        var best: (date: Date, usage: ProviderUsage)?

        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard
                    line.contains("\"token_count\""),
                    let data = line.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let timestamp = object["timestamp"] as? String,
                    let date = parseISO8601(timestamp),
                    let payload = object["payload"] as? [String: Any],
                    let rateLimits = payload["rate_limits"] as? [String: Any]
                else {
                    continue
                }

                let mapped = CodexWindowMapper.map(
                    primary: logWindow(rateLimits["primary"]),
                    secondary: logWindow(rateLimits["secondary"])
                )
                let usage = ProviderUsage(
                    provider: .codex,
                    remainingPercent5h: remainingPercent(fromUsed: mapped.fiveHour?.usedPercent),
                    remainingPercent7d: remainingPercent(fromUsed: mapped.sevenDay?.usedPercent),
                    resetAt5h: mapped.fiveHour?.resetAt,
                    resetAt7d: mapped.sevenDay?.resetAt,
                    source: .localLog,
                    error: nil,
                    plan: rateLimits["plan_type"] as? String,
                    model: nil,
                    updatedAt: Date()
                )

                if best == nil || date > best!.date {
                    best = (date, usage)
                }
            }
        }

        return best?.usage
    }

    private func logWindow(_ value: Any?) -> CodexRateWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        let minutes = dict["window_minutes"] as? Double
        return CodexRateWindow(
            usedPercent: dict["used_percent"] as? Double,
            resetAt: timestampDate(dict["resets_at"]),
            windowSeconds: minutes.map { $0 * 60 }
        )
    }

    private func rolloutFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: AppPaths.codexSessions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard
                let url = item as? URL,
                url.lastPathComponent.hasPrefix("rollout-"),
                url.pathExtension == "jsonl"
            else {
                return nil
            }
            return url
        }
    }
}
