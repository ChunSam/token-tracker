import Foundation

/// A provider's persisted 429 cooldown.
///
/// Both usage endpoints rate limit per account, and both are polled on the same
/// timer, so a provider that starts answering 429 will be hit again every refresh
/// unless something holds the app back. Claude had this; Codex did not, and would
/// hammer straight through a limit at the poll cadence.
///
/// One instance per provider, each with its own store file: a cooldown earned by
/// Claude must not silence Codex, and vice versa.
actor RateLimitState {
    private let store: RateLimitStore
    private var retryAllowedAt: Date?
    private var failureCount = 0
    private var fingerprint: String?
    private var didLoad = false

    init(store: RateLimitStore) {
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
