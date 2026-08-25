import Foundation

struct CodexUsageClient: Sendable {
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

        // `codex login` refreshes this token; Token Tracker only reads it. Once it
        // lapses the endpoint answers a bare `HTTP 401`, which tells the user
        // nothing about needing to sign in again — so name the cause here instead.
        let expiresAt = CredentialExpiry.jwtExpiry(auth.accessToken)
        if CredentialExpiry.isExpired(expiresAt) {
            throw UsageError.expiredCredentials(service: "Codex API", expiredAt: expiresAt)
        }

        let raw = try await http.getJSON(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(auth.accessToken)",
                "ChatGPT-Account-Id": auth.accountId,
                "User-Agent": "TokenTrackerMenuBar/1.0"
            ],
            serviceName: "Codex API"
        )
        guard
            let object = raw as? [String: Any],
            let usage = CodexUsageParser.parse(object: object)
        else {
            throw UsageError.invalidResponse
        }
        return usage
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
