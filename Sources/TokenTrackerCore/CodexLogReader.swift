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

                let primary = rateLimits["primary"] as? [String: Any]
                let secondary = rateLimits["secondary"] as? [String: Any]
                let usage = ProviderUsage(
                    provider: .codex,
                    remainingPercent5h: remainingPercent(fromUsed: primary?["used_percent"] as? Double),
                    remainingPercent7d: remainingPercent(fromUsed: secondary?["used_percent"] as? Double),
                    resetAt5h: timestampDate(primary?["resets_at"]),
                    resetAt7d: timestampDate(secondary?["resets_at"]),
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
