import Foundation
import TokenTrackerCore

func runClaudeUsageRegressionTests() throws {
    try verifyClaudeResponses()
    try verifyCacheLifetime()
}

private func verifyClaudeResponses() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let usage = try parse(#"{"plan_type":" max ","five_hour":{"utilization":15,"resets_at":"2026-05-27T12:00:00.000Z"},"seven_day":{"utilization":100,"resets_at":"2026-05-29T12:00:00Z"}}"#, at: now)
    expectEqual(usage.remainingPercent5h, 85, "Claude five-hour remaining")
    expectEqual(usage.remainingPercent7d, 0, "Claude seven-day remaining")
    expectEqual(usage.resetAt5h, ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z"), "Fractional reset date")
    expectEqual(usage.resetAt7d, ISO8601DateFormatter().date(from: "2026-05-29T12:00:00Z"), "Whole-second reset date")
    expectEqual(usage.plan, "max", "Claude plan is trimmed")
    expectEqual(usage.updatedAt, now, "API data records its measurement time")
    expectEqual(usage.source, .api, "Valid Claude response is marked as API data")
    expect(usage.error == nil, "Valid Claude response has no error")

    let fiveHour = try parse(#"{"five_hour":{"utilization":0},"seven_day":null}"#)
    expectEqual(fiveHour.remainingPercent5h, 100, "Zero usage is a valid measurement")
    expect(fiveHour.remainingPercent7d == nil, "Claude allows a missing seven-day window")
    let sevenDay = try parse(#"{"seven_day":{"utilization":"25.4"}}"#)
    expect(sevenDay.remainingPercent5h == nil, "Claude allows a missing five-hour window")
    expectEqual(sevenDay.remainingPercent7d, 75, "Claude accepts numeric strings")
    expectEqual(sevenDay.plan, "team", "Claude uses the credential plan as a fallback")

    let invalid = [
        "{}", "[]", "null",
        #"{"five_hour":{},"seven_day":null}"#,
        #"{"five_hour":{"utilization":true}}"#,
        #"{"five_hour":{"utilization":"unknown"}}"#,
        #"{"five_hour":{"utilization":"NaN"}}"#,
        #"{"seven_day":{"utilization":"Infinity"}}"#,
        #"{"five_hour":{"utilization":[]}}"#
    ]
    for json in invalid {
        do {
            _ = try parse(json)
            expect(false, "Claude must reject missing or invalid measurements: \(json)")
        } catch {
            expectEqual(error as? UsageError, .invalidResponse, "Invalid Claude data has a specific error")
        }
    }
    for value in [Double.nan, Double.infinity] {
        do {
            _ = try ClaudeUsageParser.parse(["five_hour": ["utilization": value]])
            expect(false, "Non-finite Claude utilization is rejected")
        } catch {
            expectEqual(error as? UsageError, .invalidResponse, "Non-finite data is not treated as API success")
        }
    }
    let bounded = try parse(#"{"five_hour":{"utilization":1e100},"seven_day":{"utilization":-1e100}}"#)
    expectEqual(bounded.remainingPercent5h, 0, "Large utilization is clamped before integer conversion")
    expectEqual(bounded.remainingPercent7d, 100, "Negative utilization is clamped before integer conversion")
}

private func verifyCacheLifetime() throws {
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    var cached = success(at: now)
    for hour in 1...13 {
        let pollAt = now.addingTimeInterval(Double(hour) * 3600)
        var current = failure(at: pollAt)
        current.codex = success(at: pollAt).codex
        cached = UsageSnapshotCachePolicy.apply(current: current, stale: cached, updatedAt: pollAt)
        expectEqual(cached.claude.source, hour <= 12 ? .staleCache : .unavailable, "Repeated failures cannot extend the twelve-hour lifetime")
        if hour <= 12 {
            expectEqual(cached.claude.remainingPercent5h, 63, "Unexpired cache keeps its value")
            expectEqual(cached.claude.updatedAt, now, "Repeated failures preserve the measurement time")
        } else {
            expect(!cached.claude.isAvailable, "Expired Claude data is discarded")
        }
        expectEqual(cached.claude.error, current.claude.error, "Cache preserves the latest failure reason")
        expectEqual(cached.codex, current.codex, "Fresh Codex data does not extend Claude's lifetime")
        expectEqual(cached.updatedAt, pollAt, "The snapshot records the poll time separately")
    }

    var staggered = success(at: now.addingTimeInterval(-2 * 3600))
    staggered.codex.updatedAt = now.addingTimeInterval(-1800)
    staggered.updatedAt = now
    let short = UsageSnapshotCachePolicy.apply(current: failure(at: now), stale: staggered, updatedAt: now, maxAge: 3600)
    expectEqual(short.claude.source, .unavailable, "Custom tolerance expires Claude independently")
    expectEqual(short.codex.source, .staleCache, "Custom tolerance keeps recent Codex data")
    expectEqual(short.codex.updatedAt, staggered.codex.updatedAt, "Codex measurement time is preserved")
    let long = UsageSnapshotCachePolicy.apply(current: failure(at: now), stale: staggered, updatedAt: now, maxAge: 48 * 3600)
    expectEqual(long.claude.source, .staleCache, "Longer configured tolerance is honored")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.json")
    let store = CacheStore(url: url)
    let measuredAt = now.addingTimeInterval(-13 * 3600)
    let firstFailureAt = now.addingTimeInterval(-3 * 3600)
    store.save(UsageSnapshotCachePolicy.apply(
        current: failure(at: firstFailureAt), stale: success(at: measuredAt), updatedAt: firstFailureAt
    ))
    guard let loaded = store.load(maxAge: 12 * 3600) else {
        expect(false, "Recent poll snapshot survives a restart")
        return
    }
    expectEqual(loaded.claude.updatedAt, measuredAt, "Disk cache preserves the measurement time")
    let expired = UsageSnapshotCachePolicy.apply(current: failure(at: now), stale: loaded, updatedAt: now)
    expect(!expired.claude.isAvailable && !expired.codex.isAvailable, "Restart does not revive expired measurements")
    expectEqual(expired.claude.error, "HTTP 429 from Claude API", "Expired cache preserves the current failure reason")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(success(at: now)).write(to: url)
    expect(store.load(maxAge: 12 * 3600) == nil, "Legacy caches with untrustworthy timestamps are discarded")
    store.save(success(at: now))
    expect(store.load(maxAge: 12 * 3600) != nil, "New cache is readable after discarding a legacy cache")
}

private func parse(_ json: String, at now: Date = Date()) throws -> ProviderUsage {
    let raw = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    return try ClaudeUsageParser.parse(raw, fallbackPlan: "team", updatedAt: now)
}

private func success(at date: Date) -> UsageSnapshot {
    func usage(_ provider: Provider) -> ProviderUsage {
        ProviderUsage(provider: provider, remainingPercent5h: 63, remainingPercent7d: 80,
                      resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: nil,
                      model: nil, updatedAt: date)
    }
    return UsageSnapshot(claude: usage(.claude), codex: usage(.codex), updatedAt: date)
}

private func failure(at date: Date) -> UsageSnapshot {
    UsageSnapshot(claude: .unavailable(.claude, error: "HTTP 429 from Claude API"),
                  codex: .unavailable(.codex, error: "HTTP 429 from Codex API"), updatedAt: date)
}
