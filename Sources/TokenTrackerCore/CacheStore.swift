import Foundation

package final class CacheStore {
    // Older caches overwrote measurement timestamps, so their age is unknowable.
    private struct Record: Codable {
        let version: Int
        let snapshot: UsageSnapshot
    }

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    package init(url: URL) {
        self.url = url
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    convenience init() {
        self.init(url: AppPaths.snapshotCache)
    }

    package func load(maxAge: TimeInterval) -> UsageSnapshot? {
        guard
            let data = try? Data(contentsOf: url),
            let record = try? decoder.decode(Record.self, from: data),
            record.version == 1,
            Date().timeIntervalSince(record.snapshot.updatedAt) <= maxAge
        else {
            return nil
        }
        return record.snapshot
    }

    package func save(_ snapshot: UsageSnapshot) {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(Record(version: 1, snapshot: snapshot))
            try data.write(to: url, options: .atomic)
            // Atomic writes replace the file via a temp file, so re-apply owner-only
            // permissions after each write rather than relying on the umask default.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
        }
    }
}
