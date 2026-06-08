import Foundation

@MainActor
struct CodexUsageClient {
    private let http: HTTPClient

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func fetch() async -> ProviderUsage {
        do {
            return try await fetchFromAPI()
        } catch {
            return .unavailable(.codex, error: error.localizedDescription)
        }
    }

    private func fetchFromAPI() async throws -> ProviderUsage {
        let auth = try readAuth()
        let raw = try await http.getJSON(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(auth.accessToken)",
                "ChatGPT-Account-Id": auth.accountId,
                "User-Agent": "TokenTrackerMenuBar/1.0"
            ]
        )
        guard
            let object = raw as? [String: Any],
            let rateLimit = object["rate_limit"] as? [String: Any]
        else {
            throw UsageError.invalidResponse
        }

        let primary = rateLimit["primary_window"] as? [String: Any]
        let secondary = rateLimit["secondary_window"] as? [String: Any]
        return ProviderUsage(
            provider: .codex,
            remainingPercent5h: remainingPercent(fromUsed: primary?["used_percent"] as? Double),
            remainingPercent7d: remainingPercent(fromUsed: secondary?["used_percent"] as? Double),
            resetAt5h: timestampDate(primary?["reset_at"]),
            resetAt7d: timestampDate(secondary?["reset_at"]),
            source: .api,
            error: nil,
            plan: object["plan_type"] as? String,
            model: nil,
            updatedAt: Date()
        )
    }

    private func readAuth() throws -> (accessToken: String, accountId: String) {
        guard
            let data = try? Data(contentsOf: AppPaths.codexAuth),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            let accountId = tokens["account_id"] as? String
        else {
            throw UsageError.missingCredentials
        }
        return (accessToken, accountId)
    }
}
