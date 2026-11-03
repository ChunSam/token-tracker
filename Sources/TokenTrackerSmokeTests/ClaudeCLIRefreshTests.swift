import Foundation
import TokenTrackerCore

/// Renewing a lapsed Claude token through Claude Code: when to try again, what the
/// CLI is started with, and then the launch itself against a stand-in, because the
/// part that can go wrong on a user's machine — no terminal, a CLI that never
/// leaves — is the part a truth table cannot see.
func runClaudeCLIRefreshTests() throws {
    let attemptedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let renewed = ClaudeCLIRefreshAttempt(attemptedAt: attemptedAt, outcome: .refreshed)
    let unchanged = ClaudeCLIRefreshAttempt(attemptedAt: attemptedAt, outcome: .unchanged)
    let notFound = ClaudeCLIRefreshAttempt(attemptedAt: attemptedAt, outcome: .cliNotFound)
    expect(ClaudeCLIRefresh.isDue(lastAttempt: nil, now: attemptedAt), "the first renewal is due at once")
    expectEqual(ClaudeCLIRefresh.nextAttempt(after: renewed), attemptedAt.addingTimeInterval(300), "a renewal waits five minutes before another")
    expectEqual(ClaudeCLIRefresh.nextAttempt(after: unchanged), attemptedAt.addingTimeInterval(1800), "a renewal that changed nothing waits half an hour")
    expectEqual(ClaudeCLIRefresh.nextAttempt(after: notFound), attemptedAt.addingTimeInterval(1800), "a missing CLI is looked for again in half an hour")
    expect(!ClaudeCLIRefresh.isDue(lastAttempt: unchanged, now: attemptedAt.addingTimeInterval(1799)), "a failed renewal is not retried early")
    expect(ClaudeCLIRefresh.isDue(lastAttempt: unchanged, now: attemptedAt.addingTimeInterval(1800)), "a failed renewal is retried on time")

    expectEqual(
        ClaudeCLIRefresh.arguments,
        ["--strict-mcp-config", "--settings", #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#],
        "the launch turns off hooks, MCP servers and Remote Control"
    )

    let environment = ClaudeCLIRefresh.launchEnvironment(
        from: [
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/x",
            "ANTHROPIC_BASE_URL": "http://127.0.0.1:1",
            "CLAUDECODE": "1",
            "CLAUDE_CODE_OAUTH_TOKEN": "token",
            "CLAUDE_CONFIG_DIR": "/elsewhere"
        ],
        binaryDirectory: "/Users/x/.local/bin"
    )
    expectEqual(environment["PATH"], "/Users/x/.local/bin:/usr/bin:/bin", "the CLI's own directory leads PATH")
    expectEqual(environment["HOME"], "/Users/x", "the rest of the environment is kept")
    expect(
        environment.keys.allSatisfy { !$0.hasPrefix("ANTHROPIC_") && !$0.hasPrefix("CLAUDE") },
        "nothing points the CLI at other credentials or another config"
    )
    expectEqual(environment["DISABLE_AUTOUPDATER"], "1", "a renewal never updates the CLI")
    expectEqual(environment["TERM"], "xterm-256color", "the terminal gets a type")
    expectEqual(ClaudeCLIRefresh.launchEnvironment(from: ["TERM": "dumb"], binaryDirectory: "/b")["TERM"], "dumb", "a terminal type already set is kept")
    expectEqual(ClaudeCLIRefresh.launchEnvironment(from: [:], binaryDirectory: "/b")["PATH"], "/b", "no PATH becomes the CLI's directory alone")

    expectEqual(
        ClaudeCLIRefresh.candidatePaths(home: "/Users/x", path: "/usr/bin:/opt/homebrew/bin:"),
        [
            "/Users/x/.local/bin/claude",
            "/Users/x/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ],
        "the install locations come first, then PATH, each once"
    )

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("token-tracker-cli-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("store").path
    FileManager.default.createFile(atPath: store, contents: Data())
    try FileManager.default.setAttributes([.modificationDate: attemptedAt], ofItemAtPath: store)
    let storeWrittenAt: @Sendable () -> Date? = {
        (try? FileManager.default.attributesOfItem(atPath: store))?[.modificationDate] as? Date
    }

    // Renews only when it has a terminal and was started the way the app starts
    // the real CLI, then waits at its prompt for the answer the refresher gives.
    let renewing = try stubCLI(in: directory, named: "renewing", body: """
        [ -t 0 ] || exit 3
        [ "$1" = "--strict-mcp-config" ] || exit 4
        [ "$DISABLE_AUTOUPDATER" = "1" ] || exit 5
        sleep 0.2
        touch '\(store)'
        read answer
        """)
    let started = Date()
    let renewal = waitFor {
        await ClaudeCLIRefresher.run(
            binary: renewing,
            workingDirectory: directory.appendingPathComponent("cwd"),
            storeWrittenAt: storeWrittenAt
        )
    }
    expectEqual(renewal, .refreshed, "a CLI that rewrites the store on a terminal counts as a renewal")
    expect(Date().timeIntervalSince(started) < 5, "the CLI leaves on the prompt's default answer instead of waiting out the timeout")

    // Never renews and never leaves: the timeout ends the wait and the process.
    let stubborn = try stubCLI(in: directory, named: "stubborn", body: """
        trap '' INT
        while :; do sleep 1; done
        """)
    try FileManager.default.setAttributes([.modificationDate: attemptedAt], ofItemAtPath: store)
    let stuck = waitFor {
        await ClaudeCLIRefresher.run(
            binary: stubborn,
            workingDirectory: directory.appendingPathComponent("cwd"),
            timeout: 0.5,
            storeWrittenAt: storeWrittenAt
        )
    }
    expectEqual(stuck, .unchanged, "a CLI that leaves the store alone is not a renewal")

    let missing = waitFor {
        await ClaudeCLIRefresher.run(
            binary: directory.appendingPathComponent("absent").path,
            workingDirectory: directory.appendingPathComponent("cwd"),
            storeWrittenAt: storeWrittenAt
        )
    }
    expectEqual(missing, .launchFailed, "a binary that cannot start is a failed launch")
}

private func stubCLI(in directory: URL, named name: String, body: String) throws -> String {
    let url = directory.appendingPathComponent(name)
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// The smoke tests are a synchronous script; this runs one async call to the end.
private func waitFor<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.value = await operation()
        done.signal()
    }
    done.wait()
    return box.value!
}
