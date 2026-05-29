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
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            // Atomic writes replace the file via a temp file, so re-apply owner-only
            // permissions after each write rather than relying on the umask default.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
        }
    }
}
