import Foundation

struct ClaudeUsageClient: Sendable {
    private let http: HTTPClient
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let rateLimitState = ClaudeRateLimitState(store: ClaudeRateLimitStore(url: AppPaths.claudeRateLimit))
    fileprivate static let defaultRateLimitCooldown: TimeInterval = 300

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func fetch() async -> ProviderUsage {
        let candidates: [TokenCandidate]
        do {
            candidates = try readTokenCandidates()
        } catch {
            return .unavailable(.claude, error: error.localizedDescription)
        }

        // Every stored token has lapsed. Spending a request on one would return an
        // opaque 401 — or a 429 that the backoff below would mistake for a quota
        // cooldown — so report the real cause and drop any cooldown that a previous
        // expired-token round already recorded.
        let usable = candidates.filter { !$0.isExpired }
        guard !usable.isEmpty else {
            await rateLimitState.clear()
            return .unavailable(
                .claude,
                error: UsageError.expiredCredentials(
                    service: "Claude API",
                    expiredAt: candidates.compactMap(\.expiresAt).max()
                ).localizedDescription
            )
        }

        // A cooldown is only binding for the credentials that earned it; signing in
        // again has to take effect immediately rather than wait it out.
        let fingerprint = TokenFingerprint.of(usable.map(\.token))
        if let error = await rateLimitState.currentError(serviceName: "Claude API", fingerprint: fingerprint) {
            return .unavailable(.claude, error: error.localizedDescription)
        }

        do {
            let usage = try await fetchFromAPI(candidates: usable)
            await rateLimitState.clear()
            return usage
        } catch let error as UsageError {
            if let retryAfter = error.rateLimitRetryAfter {
                await rateLimitState.backOff(for: retryAfter, fingerprint: fingerprint)
                let currentError = await rateLimitState.currentError(serviceName: "Claude API", fingerprint: fingerprint)
                return .unavailable(.claude, error: currentError?.localizedDescription ?? error.localizedDescription)
            }
            if case .httpStatus(429, _, nil) = error {
                await rateLimitState.backOff(for: Self.defaultRateLimitCooldown, fingerprint: fingerprint)
                let currentError = await rateLimitState.currentError(serviceName: "Claude API", fingerprint: fingerprint)
                return .unavailable(.claude, error: currentError?.localizedDescription ?? error.localizedDescription)
            }
            return .unavailable(.claude, error: error.localizedDescription)
        } catch {
            return .unavailable(.claude, error: error.localizedDescription)
        }
    }

    private func fetchFromAPI(candidates: [TokenCandidate]) async throws -> ProviderUsage {
        var lastError: UsageError = .missingCredentials
        for (index, candidate) in candidates.enumerated() {
            do {
                return try await fetchFromAPI(token: candidate.token, fallbackPlan: candidate.plan)
            } catch let error as UsageError where error.isAuthenticationFailure
                && candidate.source == .keychain
                && candidates.indices.contains(index + 1)
            {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private func fetchFromAPI(token: String, fallbackPlan: String?) async throws -> ProviderUsage {
        let raw = try await http.getJSON(
            url: usageURL,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "TokenTrackerMenuBar/1.0"
            ],
            timeout: 10,
            serviceName: "Claude API"
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
            plan: readPlan(from: object) ?? fallbackPlan,
            model: nil,
            updatedAt: Date()
        )
    }

    private func readTokenCandidates() throws -> [TokenCandidate] {
        let rawCandidates = [
            readCredentialFromKeychain().flatMap { TokenCandidate(source: .keychain, credential: $0) },
            readCredentialFromFile().flatMap { TokenCandidate(source: .credentialsFile, credential: $0) }
        ].compactMap { $0 }

        var candidates: [TokenCandidate] = []
        var seenTokens = Set<String>()
        for candidate in rawCandidates where seenTokens.insert(candidate.token).inserted {
            candidates.append(candidate)
        }

        if candidates.isEmpty {
            throw UsageError.missingCredentials
        }
        return candidates
    }

    private func readCredentialFromKeychain() -> ClaudeCredential? {
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
            return ClaudeCredential(
                accessToken: token,
                plan: readPlan(from: claudeOauth),
                expiresAt: CredentialExpiry.epochMillisecondsDate(claudeOauth["expiresAt"])
            )
        } catch {
            return nil
        }
    }

    private func readCredentialFromFile() -> ClaudeCredential? {
        guard
            let data = try? Data(contentsOf: AppPaths.claudeCredentials),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let claudeOauth = json["claudeAiOauth"] as? [String: Any],
            let token = claudeOauth["accessToken"] as? String
        else {
            return nil
        }
        return ClaudeCredential(
            accessToken: token,
            plan: readPlan(from: claudeOauth),
            expiresAt: CredentialExpiry.epochMillisecondsDate(claudeOauth["expiresAt"])
        )
    }

    private func readPlan(from object: [String: Any]) -> String? {
        for key in ["plan_type", "planType", "subscription_type", "subscriptionType", "tier", "rate_limit_tier", "rateLimitTier"] {
            if let plan = normalizedString(object[key]) {
                return plan
            }
        }
        return nil
    }

    private func normalizedString(_ value: Any?) -> String? {
        guard let text = value as? String else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ClaudeCredential {
    let accessToken: String
    let plan: String?
    let expiresAt: Date?
}

private struct TokenCandidate {
    let source: TokenSource
    let token: String
    let plan: String?
    let expiresAt: Date?

    init?(source: TokenSource, credential: ClaudeCredential) {
        guard !credential.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.source = source
        self.token = credential.accessToken
        self.plan = credential.plan
        self.expiresAt = credential.expiresAt
    }

    var isExpired: Bool {
        CredentialExpiry.isExpired(expiresAt)
    }
}

private enum TokenSource {
    case keychain
    case credentialsFile
}

private actor ClaudeRateLimitState {
    private let store: ClaudeRateLimitStore
    private var retryAllowedAt: Date?
    private var failureCount = 0
    private var fingerprint: String?
    private var didLoad = false

    init(store: ClaudeRateLimitStore) {
        self.store = store
    }

    /// Seed the in-memory cooldown from disk on first use so a relaunch during a
    /// cooldown does not immediately re-fire a still-rate-limited request.
    private func loadIfNeeded() {
        guard !didLoad else {
            return
        }
        didLoad = true
        if let state = store.load() {
            retryAllowedAt = state.retryAllowedAt
            failureCount = state.failureCount
            fingerprint = state.fingerprint
        }
    }

    func currentError(serviceName: String, fingerprint: String) -> UsageError? {
        loadIfNeeded()
        guard let retryAllowedAt else {
            return nil
        }

        // A cooldown only binds the credentials it was recorded against. A record
        // that names different credentials — or, from a build before fingerprints
        // were stored, names none at all — cannot be shown to apply to the token in
        // hand, so the token gets a fresh attempt. Dropping one costs a single
        // request that re-establishes the cooldown if the limit is real; honoring
        // one wrongly blocks refreshes for up to the full escalated cooldown.
        guard self.fingerprint == fingerprint else {
            reset()
            return nil
        }

        let remaining = retryAllowedAt.timeIntervalSinceNow
        if remaining <= 0 {
            self.retryAllowedAt = nil
            store.clear()
            return nil
        }
        return .httpStatus(code: 429, service: serviceName, retryAfter: remaining)
    }

    func backOff(for retryAfter: TimeInterval, fingerprint: String) {
        loadIfNeeded()
        if self.fingerprint != fingerprint {
            // New credentials start their own backoff ladder rather than inheriting
            // the escalation earned by a token that is no longer in use.
            failureCount = 0
            self.fingerprint = fingerprint
        }
        // Escalate the cooldown per consecutive 429 and add jitter so repeated
        // rate limiting backs off further instead of retrying at a fixed cadence.
        let cooldown = RateLimitBackoff.cooldown(
            retryAfter: retryAfter,
            failureCount: failureCount,
            jitter: Double.random(in: 0...RateLimitBackoff.jitterFraction)
        )
        failureCount += 1
        let allowedAt = Date().addingTimeInterval(cooldown)
        retryAllowedAt = allowedAt
        store.save(.init(retryAllowedAt: allowedAt, failureCount: failureCount, fingerprint: fingerprint))
    }

    func clear() {
        loadIfNeeded()
        reset()
    }

    private func reset() {
        failureCount = 0
        retryAllowedAt = nil
        fingerprint = nil
        store.clear()
    }
}
