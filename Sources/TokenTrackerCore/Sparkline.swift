import Foundation

/// Reduces stored history into a compact remaining-% series for one
/// provider/window, downsampled to a menu-friendly width. Pure — no network.
public enum SparklineSeries {
    public static func build(
        entries: [UsageHistoryEntry],
        provider: Provider,
        window: ForecastWindow,
        maxPoints: Int = 20
    ) -> [Int] {
        let values = entries
            .sorted { $0.recordedAt < $1.recordedAt }
            .compactMap { remaining($0.snapshot.usage(for: provider), window) }

        guard maxPoints > 0, values.count > maxPoints else { return values }

        var result: [Int] = []
        result.reserveCapacity(maxPoints)
        for bucket in 0..<maxPoints {
            let start = bucket * values.count / maxPoints
            let end = max(start + 1, (bucket + 1) * values.count / maxPoints)
            let slice = values[start..<end]
            result.append(slice.reduce(0, +) / slice.count)
        }
        return result
    }

    private static func remaining(_ usage: ProviderUsage, _ window: ForecastWindow) -> Int? {
        switch window {
        case .fiveHour: return usage.remainingPercent5h
        case .sevenDay: return usage.remainingPercent7d
        }
    }
}

/// Renders a 0–100 series as a Unicode block sparkline (absolute scale, so the
/// level and slope are both visible). Shared across platforms — no drawing code.
public enum SparklineText {
    private static let blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    public static func render(_ series: [Int]) -> String {
        guard series.count >= 2 else { return "" }
        return series.map { value in
            let clamped = min(100, max(0, value))
            let index = min(blocks.count - 1, clamped * blocks.count / 100)
            return blocks[index]
        }.joined()
    }
}
