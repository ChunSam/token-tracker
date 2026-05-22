import Foundation

struct ClaudeUsageClient {
    private let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func fetch() async -> ProviderUsage {
        do {
            return try await fetchFromAPI()
        } catch {
            return .unavailable(.claude, error: error.localizedDescription)
        }
    }

    private func fetchFromAPI() async throws -> ProviderUsage {
        let token = try readToken()
        let raw = try await http.getJSON(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "TokenTrackerMenuBar/1.0"
            ]
        )
        guard let object = raw as? [String: Any] else {
            throw UsageError.invalidResponse
        }

        let fiveHour = object["five_hour"] as? [String: Any]
        let sevenDay = object["seven_day"] as? [String: Any]
        return ProviderUsage(
            provider: .claude,
            remainingPercent5h: remainingPercent(fromUsed: fiveHour?["utilization"] as? Double),
            remainingPercent7d: remainingPercent(fromUsed: sevenDay?["utilization"] as? Double),
            resetAt5h: isoDate(fiveHour?["resets_at"] as? String),
            resetAt7d: isoDate(sevenDay?["resets_at"] as? String),
            source: .api,
            error: nil,
            plan: nil,
            model: nil,
            updatedAt: Date()
        )
    }

    private func readToken() throws -> String {
        if let token = readTokenFromKeychain() {
            return token
        }
        if let token = readTokenFromFile() {
            return token
        }
        throw UsageError.missingCredentials
    }

    private func readTokenFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard
                let text = String(data: data, encoding: .utf8),
                let jsonData = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let claudeOauth = json["claudeAiOauth"] as? [String: Any],
                let token = claudeOauth["accessToken"] as? String
            else {
                return nil
            }
            return token
        } catch {
            return nil
        }
    }

    private func readTokenFromFile() -> String? {
        guard
            let data = try? Data(contentsOf: AppPaths.claudeCredentials),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let claudeOauth = json["claudeAiOauth"] as? [String: Any],
            let token = claudeOauth["accessToken"] as? String
        else {
            return nil
        }
        return token
    }
}
