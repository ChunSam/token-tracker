import Foundation

func timestampDate(_ value: Any?) -> Date? {
    if let number = value as? Double { return Date(timeIntervalSince1970: number) }
    if let number = value as? Int { return Date(timeIntervalSince1970: TimeInterval(number)) }
    return nil
}

func isoDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    return makeISO8601Formatter().date(from: value)
        ?? makeISO8601Formatter(includeFractionalSeconds: false).date(from: value)
}

func parseISO8601(_ value: String) -> Date? {
    makeISO8601Formatter().date(from: value)
        ?? makeISO8601Formatter(includeFractionalSeconds: false).date(from: value)
}

private func makeISO8601Formatter(includeFractionalSeconds: Bool = true) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = includeFractionalSeconds
        ? [.withInternetDateTime, .withFractionalSeconds]
        : [.withInternetDateTime]
    return formatter
}
