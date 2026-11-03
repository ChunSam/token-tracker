import Foundation

/// One try at getting Claude Code to renew its own stored token.
public struct ClaudeCLIRefreshAttempt: Sendable, Equatable {
    public enum Outcome: String, Sendable {
        /// The credential store was rewritten while the CLI ran.
        case refreshed
        /// The CLI ran and left the store alone: its refresh token has lapsed as
        /// well, which only `/login` fixes, or it stopped on a screen of its own.
        case unchanged
        /// No `claude` executable in any of the places it installs to.
        case cliNotFound
        case launchFailed
    }

    public let attemptedAt: Date
    public let outcome: Outcome

    public init(attemptedAt: Date, outcome: Outcome) {
        self.attemptedAt = attemptedAt
        self.outcome = outcome
    }
}

/// Renewing an expired Claude token without the user opening a terminal.
///
/// The access token lives ~8h and only Claude Code may renew it. Its refresh token
/// is single-use, so spending it here would sign the CLI out — the bug CodexBar
/// shipped and then backed out — and Anthropic's terms bar third-party apps from
/// holding Claude credentials of their own. What remains is running the unmodified
/// CLI, which renews the stored token while it starts: measured on 2.1.314 at
/// ~0.7s after launch, before its first screen, with no model request. The launch
/// runs in a folder Claude Code has never been told to trust, so it stops at the
/// trust prompt and never reaches hooks, plugins or a session.
///
/// Mirrors `windows/TokenTracker.Windows.Core/ClaudeCliRefresh.cs`.
public enum ClaudeCLIRefresh {
    /// How long the CLI gets to rewrite the store. Startup renewal took under a
    /// second when measured; the rest is room for a slow network.
    public static let timeout: TimeInterval = 15

    /// After a renewal, the earliest next try. A fresh token lives for hours, so
    /// another lapse this soon means something else is wrong, and it is not worth
    /// a launch on every poll.
    public static let retryAfterRefresh: TimeInterval = 5 * 60

    /// After a try that changed nothing or found no CLI. The refresh token itself
    /// may have lapsed, which only `/login` fixes, so try rarely rather than on
    /// every poll.
    public static let retryAfterFailure: TimeInterval = 30 * 60

    public static func nextAttempt(after attempt: ClaudeCLIRefreshAttempt) -> Date {
        attempt.attemptedAt.addingTimeInterval(
            attempt.outcome == .refreshed ? retryAfterRefresh : retryAfterFailure
        )
    }

    /// No try yet is due at once.
    public static func isDue(lastAttempt: ClaudeCLIRefreshAttempt?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now >= nextAttempt(after: lastAttempt)
    }

    /// Belt and braces for a launch that should only start up: no user hooks
    /// (SessionStart and the rest would otherwise run), no MCP servers, no Remote
    /// Control. The untrusted folder already keeps all of them from running.
    public static let arguments: [String] = [
        "--strict-mcp-config",
        "--settings", #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#
    ]

    /// The app's own environment, minus anything that would point the CLI at other
    /// credentials or another config directory — the app only reads the default
    /// store, so that is the one to renew. The binary's directory goes first on
    /// PATH, since an npm install is a script that needs its `node` alongside.
    public static func launchEnvironment(from base: [String: String], binaryDirectory: String) -> [String: String] {
        var environment = base.filter { key, _ in
            !key.hasPrefix("ANTHROPIC_") && !key.hasPrefix("CLAUDE")
        }
        let path = environment["PATH"] ?? ""
        environment["PATH"] = path.isEmpty ? binaryDirectory : binaryDirectory + ":" + path
        // Renewing a token is no reason to replace the user's installation.
        environment["DISABLE_AUTOUPDATER"] = "1"
        if environment["TERM"] == nil {
            environment["TERM"] = "xterm-256color"
        }
        return environment
    }

    /// Where `claude` installs, in the order to try. A menu bar app inherits
    /// launchd's bare PATH, so the usual locations are named rather than left to it.
    public static func candidatePaths(home: String, path: String?) -> [String] {
        var paths = [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        for directory in (path ?? "").split(separator: ":") where !directory.isEmpty {
            paths.append(directory + "/claude")
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// The first installed `claude`, or `nil`.
    public static func locate(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        path: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        candidatePaths(home: home, path: path).first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Runs the CLI when a try is due and reports whether the store moved.
///
/// Sendable by its lock: the usage client is a value type shared across refreshes,
/// and two overlapping fetches must not start two CLIs.
public final class ClaudeCLIRefresher: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAttemptStorage: ClaudeCLIRefreshAttempt?
    private var inFlight = false
    private let workingDirectory: URL
    private let storeWrittenAt: @Sendable () -> Date?

    public convenience init() {
        self.init(
            workingDirectory: AppPaths.claudeCLIRefreshDirectory,
            storeWrittenAt: {
                ClaudeCredentialSource.detect(credentialsFileURL: AppPaths.claudeCredentials).lastWrittenAt
            }
        )
    }

    init(workingDirectory: URL, storeWrittenAt: @escaping @Sendable () -> Date?) {
        self.workingDirectory = workingDirectory
        self.storeWrittenAt = storeWrittenAt
    }

    public var lastAttempt: ClaudeCLIRefreshAttempt? {
        lock.lock()
        defer { lock.unlock() }
        return lastAttemptStorage
    }

    /// True when the credential store was rewritten, so it is worth reading again.
    func refreshIfDue(now: Date = Date()) async -> Bool {
        guard reserve(now: now) else { return false }
        let outcome = await attempt()
        finish(ClaudeCLIRefreshAttempt(attemptedAt: now, outcome: outcome))
        return outcome == .refreshed
    }

    private func finish(_ attempt: ClaudeCLIRefreshAttempt) {
        lock.lock()
        defer { lock.unlock() }
        lastAttemptStorage = attempt
        inFlight = false
    }

    private func reserve(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !inFlight, ClaudeCLIRefresh.isDue(lastAttempt: lastAttemptStorage, now: now) else {
            return false
        }
        inFlight = true
        return true
    }

    private func attempt() async -> ClaudeCLIRefreshAttempt.Outcome {
        guard let binary = ClaudeCLIRefresh.locate() else {
            return .cliNotFound
        }
        return await Self.run(binary: binary, workingDirectory: workingDirectory, storeWrittenAt: storeWrittenAt)
    }

    /// Starts `binary` on a pseudo-terminal — the CLI only takes its interactive
    /// path, the one measured to renew on startup, when it has one — and waits for
    /// the store to move. Public so the smoke tests can drive it with a stand-in.
    public static func run(
        binary: String,
        arguments: [String] = ClaudeCLIRefresh.arguments,
        workingDirectory: URL,
        timeout: TimeInterval = ClaudeCLIRefresh.timeout,
        storeWrittenAt: @Sendable () -> Date?
    ) async -> ClaudeCLIRefreshAttempt.Outcome {
        do {
            try FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return .launchFailed
        }

        var primary: Int32 = -1
        var secondary: Int32 = -1
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &size) == 0 else {
            return .launchFailed
        }
        defer { close(primary) }
        _ = fcntl(primary, F_SETFL, fcntl(primary, F_GETFL) | O_NONBLOCK)
        let terminal = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)

        let before = storeWrittenAt()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = ClaudeCLIRefresh.launchEnvironment(
            from: ProcessInfo.processInfo.environment,
            binaryDirectory: (binary as NSString).deletingLastPathComponent
        )
        process.currentDirectoryURL = workingDirectory
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        do {
            try process.run()
        } catch {
            return .launchFailed
        }
        try? terminal.close()

        func storeMoved() -> Bool {
            // A store that reads as missing is mid-write, not renewed.
            guard let after = storeWrittenAt() else { return false }
            return after != before
        }

        var refreshed = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            drain(primary)
            if storeMoved() {
                refreshed = true
                break
            }
            if !process.isRunning {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        refreshed = refreshed || storeMoved()

        if refreshed {
            // Let a write that is still settling finish before the CLI is asked to go.
            await wait(for: process, upTo: 1, draining: primary)
        }
        if process.isRunning {
            // The trust prompt's default answer is "No, exit": take it, the way a
            // person would.
            _ = "\r".withCString { write(primary, $0, 1) }
            await wait(for: process, upTo: 3, draining: primary)
        }
        if process.isRunning {
            process.terminate()
            await wait(for: process, upTo: 2, draining: primary)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        return refreshed ? .refreshed : .unchanged
    }

    /// The CLI stalls once the terminal buffer fills, so what it draws is read and
    /// dropped.
    private static func drain(_ descriptor: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while read(descriptor, &buffer, buffer.count) > 0 {}
    }

    private static func wait(for process: Process, upTo seconds: TimeInterval, draining descriptor: Int32) async {
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline {
            drain(descriptor)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
