import Foundation

final class CacheStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL = AppPaths.snapshotCache) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(maxAge: TimeInterval) -> UsageSnapshot? {
        guard
            let data = try? Data(contentsOf: url),
            let snapshot = try? decoder.decode(UsageSnapshot.self, from: data),
            Date().timeIntervalSince(snapshot.updatedAt) <= maxAge
        else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: UsageSnapshot) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
        }
    }
}
