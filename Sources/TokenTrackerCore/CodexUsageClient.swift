import Foundation

struct CodexUsageClient: Sendable {
    private let http: HTTPClient
    private let rateLimitState = RateLimitState(store: RateLimitStore(url: AppPaths.codexRateLimit))
    private static let defaultRateLimitCooldown: TimeInterval = 300

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func fetch() async -> ProviderUsage {
        let auth: CodexAuth
        do {
            auth = try readAuth()
        } catch {
            return .unavailable(.codex, error: error.localizedDescription)
        }

        // `codex login` refreshes this token; Token Tracker only reads it. Once it
        // lapses the endpoint answers a bare `HTTP 401`, which tells the user
        // nothing about needing to sign in again — so name the cause here instead.
        let expiresAt = CredentialExpiry.jwtExpiry(auth.accessToken)
        if CredentialExpiry.isExpired(expiresAt) {
            // An expired token is not a rate limit; drop any cooldown a previous
            // expired-token round recorded so signing in again takes effect at once.
            await rateLimitState.clear()
            return .unavailable(
                .codex,
                error: UsageError.expiredCredentials(service: "Codex API", expiredAt: expiresAt).localizedDescription
            )
        }

        let fingerprint = TokenFingerprint.of([auth.accessToken])
        if let error = await rateLimitState.currentError(serviceName: "Codex API", fingerprint: fingerprint) {
            return .unavailable(.codex, error: error.localizedDescription)
        }

        do {
            let usage = try await fetchFromAPI(auth: auth)
            await rateLimitState.clear()
            return usage
        } catch let error as UsageError {
            // Without this the poll timer walked straight back into the limit every
            // refresh; Claude has held a cooldown for a while, Codex never did.
            if let retryAfter = error.rateLimitRetryAfter ?? headerlessRateLimitCooldown(error) {
                await rateLimitState.backOff(for: retryAfter, fingerprint: fingerprint)
                let currentError = await rateLimitState.currentError(serviceName: "Codex API", fingerprint: fingerprint)
                return .unavailable(.codex, error: currentError?.localizedDescription ?? error.localizedDescription)
            }
            return .unavailable(.codex, error: error.localizedDescription)
        } catch {
            return .unavailable(.codex, error: error.localizedDescription)
        }
    }

    /// A 429 that carried no `Retry-After` still needs a cooldown, just a guessed one.
    private func headerlessRateLimitCooldown(_ error: UsageError) -> TimeInterval? {
        if case .httpStatus(429, _, nil) = error { return Self.defaultRateLimitCooldown }
        return nil
    }

    private func fetchFromAPI(auth: CodexAuth) async throws -> ProviderUsage {
        let raw = try await http.getJSON(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(auth.accessToken)",
                "ChatGPT-Account-Id": auth.accountId,
                "User-Agent": "TokenTrackerMenuBar/1.0"
            ],
            timeout: 10,
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

    private func readAuth() throws -> CodexAuth {
        guard
            let data = try? Data(contentsOf: AppPaths.codexAuth),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            let accountId = tokens["account_id"] as? String
        else {
            throw UsageError.missingCredentials
        }
        return CodexAuth(accessToken: accessToken, accountId: accountId)
    }
}

private struct CodexAuth {
    let accessToken: String
    let accountId: String
}
