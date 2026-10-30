import Foundation
import TokenTrackerCore

/// The status-line bridge, end to end: the record policy in Core, and then the
/// shell script itself, because the one rule that makes this safe — a replayed
/// payload does not look like a new measurement — lives in both halves.
func runClaudeStatusLineTests() throws {
    let now = Date(timeIntervalSince1970: 1_793_300_000)
    let reset5h = now.addingTimeInterval(3600)
    let reset7d = now.addingTimeInterval(86_400)

    func payload(
        version: Int = ClaudeStatusLineBridge.version,
        measuredAt: Date? = now,
        writtenAt: Date? = now,
        fiveHour: (used: Double, reset: Date)? = (23.5, reset5h),
        sevenDay: (used: Double, reset: Date)? = (41.2, reset7d)
    ) -> Data {
        var limits: [String: Any] = [:]
        if let fiveHour {
            limits["five_hour"] = ["used_percentage": fiveHour.used, "resets_at": fiveHour.reset.timeIntervalSince1970]
        }
        if let sevenDay {
            limits["seven_day"] = ["used_percentage": sevenDay.used, "resets_at": sevenDay.reset.timeIntervalSince1970]
        }
        var object: [String: Any] = ["version": version, "provider": "claude", "rate_limits": limits]
        if let measuredAt { object["measured_at"] = measuredAt.timeIntervalSince1970 }
        if let writtenAt { object["written_at"] = writtenAt.timeIntervalSince1970 }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    // Both windows present: used percentages become remaining, resets carry over.
    let record = ClaudeStatusLineBridge.record(fromJSON: payload(), now: now)
    expectEqual(record?.measuredAt, now, "the measurement time is read from the record")
    let usage = ClaudeStatusLineBridge.usage(record, apiError: nil, now: now)
    expectEqual(usage?.source, .statusLine, "a status-line reading is not labelled as an API measurement")
    expectEqual(usage?.remainingPercent5h, 77, "23.5% used leaves 77% of the 5h window")
    expectEqual(usage?.remainingPercent7d, 59, "41.2% used leaves 59% of the 7d window")
    expectEqual(usage?.resetAt5h, reset5h, "the 5h reset instant carries through")
    expectEqual(usage?.resetAt7d, reset7d, "the 7d reset instant carries through")
    expectEqual(usage?.updatedAt, now, "the reading is stamped with the measurement time, not the poll time")

    // Either window can be absent, and one window is enough.
    let fiveOnly = ClaudeStatusLineBridge.usage(
        ClaudeStatusLineBridge.record(fromJSON: payload(sevenDay: nil), now: now),
        apiError: nil,
        now: now
    )
    expectEqual(fiveOnly?.remainingPercent5h, 77, "a record with only the 5h window still reports it")
    expect(fiveOnly?.remainingPercent7d == nil, "an absent 7d window reports nothing rather than zero")
    let sevenOnly = ClaudeStatusLineBridge.usage(
        ClaudeStatusLineBridge.record(fromJSON: payload(fiveHour: nil), now: now),
        apiError: nil,
        now: now
    )
    expectEqual(sevenOnly?.remainingPercent7d, 59, "a record with only the 7d window still reports it")
    expect(
        ClaudeStatusLineBridge.record(fromJSON: payload(fiveHour: nil, sevenDay: nil), now: now) == nil,
        "a record with neither window is not a reading"
    )

    // Claude Code drops a window once its reset passes, so one still sitting in
    // the file describes a window instance that no longer exists.
    let expiredFiveHour = ClaudeStatusLineBridge.record(
        fromJSON: payload(fiveHour: (99, now.addingTimeInterval(-1))),
        now: now
    )
    expect(expiredFiveHour?.usedPercent5h == nil, "a window whose reset has passed is dropped")
    expectEqual(expiredFiveHour?.usedPercent7d, 41.2, "dropping one expired window keeps the other")

    // A malformed or future record is not a reading. Ageing a measurement stamped
    // in the future would make it look permanently fresh.
    expect(ClaudeStatusLineBridge.record(fromJSON: Data("{".utf8), now: now) == nil, "truncated JSON is not a reading")
    expect(ClaudeStatusLineBridge.record(fromJSON: payload(version: 2), now: now) == nil, "an unknown format version is not read")
    expect(ClaudeStatusLineBridge.record(fromJSON: payload(measuredAt: nil), now: now) == nil, "a record without a measurement time is not read")
    expect(
        ClaudeStatusLineBridge.record(
            fromJSON: payload(measuredAt: now.addingTimeInterval(ClaudeStatusLineBridge.clockSkew + 60)),
            now: now
        ) == nil,
        "a measurement stamped in the future is not read"
    )

    // The trap this whole design exists to avoid: the status-line command re-runs
    // on a timer, and a re-run is not a new measurement. written_at moves, so a
    // reading aged by it would never expire; measured_at does not, so it does.
    let replayed = ClaudeStatusLineBridge.record(
        fromJSON: payload(measuredAt: now.addingTimeInterval(-7200), writtenAt: now),
        now: now
    )
    expectEqual(replayed?.writtenAt, now, "the replay time is recorded")
    expect(
        ClaudeStatusLineBridge.usage(replayed, apiError: nil, now: now) == nil,
        "replaying an old measurement does not make it current"
    )
    let atTheEdge = ClaudeStatusLineBridge.record(
        fromJSON: payload(measuredAt: now.addingTimeInterval(-ClaudeStatusLineBridge.freshnessWindow + 1)),
        now: now
    )
    expect(
        ClaudeStatusLineBridge.usage(atTheEdge, apiError: nil, now: now) != nil,
        "a measurement inside the freshness window is still current"
    )

    // A stale status-line reading hands over to the ordinary cache path rather
    // than presenting itself as live: the last good value keeps showing, but
    // labelled as cached, and it expires on the measurement's own clock.
    let staleReading = ProviderUsage(
        provider: .claude,
        remainingPercent5h: 77,
        remainingPercent7d: 59,
        resetAt5h: reset5h,
        resetAt7d: reset7d,
        source: .statusLine,
        error: nil,
        plan: nil,
        model: nil,
        updatedAt: now.addingTimeInterval(-3600)
    )
    let carried = UsageSnapshotCachePolicy.apply(
        current: UsageSnapshot(
            claude: .unavailable(.claude, error: "Credentials expired for Claude API"),
            codex: .unavailable(.codex, error: "Timed out"),
            updatedAt: now
        ),
        stale: UsageSnapshot(claude: staleReading, codex: .unavailable(.codex, error: "x"), updatedAt: now),
        updatedAt: now,
        maxAge: 12 * 3600
    )
    expectEqual(carried.claude.source, .staleCache, "an aged-out status-line reading is carried as cached data")
    expectEqual(carried.claude.remainingPercent5h, 77, "the last status-line value keeps showing while it is in tolerance")
    expectEqual(carried.claude.updatedAt, staleReading.updatedAt, "carrying it forward does not refresh its measurement time")
    let beyondTolerance = UsageSnapshotCachePolicy.apply(
        current: UsageSnapshot(
            claude: .unavailable(.claude, error: "Credentials expired for Claude API"),
            codex: .unavailable(.codex, error: "Timed out"),
            updatedAt: now
        ),
        stale: UsageSnapshot(claude: staleReading, codex: .unavailable(.codex, error: "x"), updatedAt: now),
        updatedAt: now,
        maxAge: 1800
    )
    expectEqual(beyondTolerance.claude.source, .unavailable, "past tolerance the status-line reading is gone, not frozen")

    // History records measurements this app took and timestamps them with the
    // poll it took them on. A status-line reading is re-read on every poll, so
    // admitting it would append one measurement under a run of fresh timestamps
    // and tell the forecast that usage had stopped moving.
    let liveReading = ProviderUsage(
        provider: .claude,
        remainingPercent5h: 77,
        remainingPercent7d: 59,
        resetAt5h: reset5h,
        resetAt7d: reset7d,
        source: .statusLine,
        error: nil,
        plan: nil,
        model: nil,
        updatedAt: now
    )
    let forHistory = UsageHistoryPolicy.measurementsOnly(
        UsageSnapshot(claude: liveReading, codex: .unavailable(.codex, error: "x"), updatedAt: now)
    )
    expect(forHistory.claude.remainingPercent5h == nil, "a status-line reading does not enter history")
    expect(forHistory.claude.remainingPercent7d == nil, "a status-line reading does not enter the trend or forecast")

    // The menu says where the number came from, and still names the fix for
    // whatever stopped the API path.
    let issue = UsageIssueFormatter.issue(
        for: ProviderUsage(
            provider: .claude,
            remainingPercent5h: 77,
            remainingPercent7d: 59,
            resetAt5h: reset5h,
            resetAt7d: reset7d,
            source: .statusLine,
            error: "Credentials expired for Claude API",
            plan: nil,
            model: nil,
            updatedAt: now
        )
    )
    expectEqual(issue.kind, .statusLine, "a status-line reading reads as its own status, not as OK")
    expectEqual(issue.technicalDetail, "Credentials expired for Claude API", "the reason the API path failed is kept")
    expectEqual(
        issue.recovery,
        Localizer(language: .english).text(.recoverySignInAgainClaude),
        "showing status-line numbers still tells the user to sign in again"
    )
    for language in [AppLanguage.english, .korean] {
        let localizer = Localizer(language: language)
        for key in [L10nKey.statusFromStatusLine, .statusFromStatusLineDetail] {
            expect(localizer.text(key) != key.rawValue, "\(language.rawValue) has a string for \(key.rawValue)")
        }
    }

    // The countdown beside the number: a status-line window is live (an expired
    // one was dropped on the way in) and the reading is fresh, so the time is
    // real. A cached one has neither property.
    expectEqual(
        DisplayFormatter.resetCountdownSuffix(liveReading, showResetCountdown: true),
        " \(DisplayFormatter.formatResetCompact(reset5h)!)",
        "a status-line reading shows its reset countdown"
    )
    expectEqual(
        DisplayFormatter.resetCountdownSuffix(carried.claude, showResetCountdown: true),
        "",
        "a cached reading still shows no countdown"
    )

    try runStatusLineBridgeScriptTests()
}

/// Drives `scripts/claude-statusline-bridge.sh` the way Claude Code does. The
/// script is where "a re-run is not a new measurement" is actually decided, and
/// it is the one piece of this feature that no type checker looks at.
private func runStatusLineBridgeScriptTests() throws {
    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("scripts/claude-statusline-bridge.sh")
    guard FileManager.default.fileExists(atPath: script.path) else {
        // Built away from the checkout; the Core truth table above still ran.
        return
    }

    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("token-tracker-statusline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("claude-statusline.json")

    let reset5h = Int(Date().timeIntervalSince1970) + 3600
    let reset7d = Int(Date().timeIntervalSince1970) + 86_400

    /// Runs the bridge with a status-line payload, wrapping an inner command
    /// exactly as a user's configured status line would be wrapped.
    func run(used5h: Double?, inner: [String] = ["true"]) throws -> String {
        var limits: [String] = []
        if let used5h {
            limits.append("\"five_hour\":{\"used_percentage\":\(used5h),\"resets_at\":\(reset5h)}")
        }
        limits.append("\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":\(reset7d)}")
        let payload = """
        {"session_id":"s-123","transcript_path":"/tmp/t.jsonl","model":{"id":"claude-opus-5"},\
        "rate_limits":{\(limits.joined(separator: ","))}}
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "--"] + inner
        process.environment = ProcessInfo.processInfo.environment
            .merging(["TOKEN_TRACKER_STATUSLINE_FILE": output.path]) { _, new in new }
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data(payload.utf8))
        try stdin.fileHandleForWriting.close()
        let printed = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expectEqual(process.terminationStatus, 0, "the bridge exits cleanly")
        return String(data: printed, encoding: .utf8) ?? ""
    }

    // The user's own status line keeps printing. This is the requirement that
    // outranks everything else here: a bridge that eats the status line is worse
    // than no bridge.
    let printed = try run(used5h: 23.5, inner: ["sh", "-c", "cat >/dev/null; printf 'MY STATUS LINE'"])
    expectEqual(printed, "MY STATUS LINE", "the wrapped status-line command still prints its own output")

    func read() throws -> ClaudeStatusLineRecord {
        let data = try Data(contentsOf: output)
        guard let record = ClaudeStatusLineBridge.record(fromJSON: data, now: Date()) else {
            fputs("FAIL: the bridge wrote a record Core cannot read\n", stderr)
            exit(1)
        }
        return record
    }

    let first = try read()
    expectEqual(first.usedPercent5h, 23.5, "the 5h percentage is recorded")
    expectEqual(first.usedPercent7d, 41.2, "the 7d percentage is recorded")
    expectEqual(first.measuredAt, first.writtenAt, "a first reading was measured when it was written")

    // Only usage. Everything else the status line is handed — the session id, the
    // transcript path, the model — is read and dropped.
    let onDisk = try String(contentsOf: output, encoding: .utf8)
    for leaked in ["s-123", "transcript", "claude-opus-5", "session_id"] {
        expect(!onDisk.contains(leaked), "the bridge file does not carry \(leaked)")
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
    expectEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, "the bridge file is readable only by its owner")

    // Age the record on disk, so "preserved" and "recomputed" are two different
    // numbers rather than two runs landing in the same second.
    let aged = Int(Date().addingTimeInterval(-7200).timeIntervalSince1970)
    func backdate() throws {
        let record = "{\"version\":\(ClaudeStatusLineBridge.version),\"provider\":\"claude\","
            + "\"measured_at\":\(aged),\"written_at\":\(aged),\"rate_limits\":{"
            + "\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":\(reset5h)},"
            + "\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":\(reset7d)}}}"
        try Data(record.utf8).write(to: output)
    }

    // Same numbers again: a re-run, not a measurement. This is the rule the whole
    // format exists for — the status-line command re-runs on the CLI's schedule.
    try backdate()
    _ = try run(used5h: 23.5)
    expectEqual(
        Int(try read().measuredAt.timeIntervalSince1970),
        aged,
        "an unchanged payload does not advance the measurement time"
    )
    expect(
        Int(try read().writtenAt.timeIntervalSince1970) > aged,
        "an unchanged payload still records that the bridge ran"
    )

    // Numbers moved: a measurement.
    try backdate()
    _ = try run(used5h: 44.0)
    let advanced = try read()
    expectEqual(advanced.usedPercent5h, 44.0, "a changed payload is recorded")
    expect(
        Int(advanced.measuredAt.timeIntervalSince1970) > aged,
        "a changed payload advances the measurement time"
    )

    // A second session rendering a staler copy of the same window must not drag
    // the record backwards: within one window instance, usage only climbs.
    _ = try run(used5h: 30.0)
    expectEqual(try read().usedPercent5h, 44.0, "a lower percentage for the same window does not overwrite a newer one")
    expectEqual(try read().measuredAt, advanced.measuredAt, "an older concurrent reading does not advance the measurement time")

    // Early in a session, or on a plan without them, rate_limits is absent. That
    // must not erase what is already known.
    _ = try run(used5h: nil)
    expectEqual(try read().usedPercent5h, 44.0, "a payload missing one window keeps the window already recorded")
}
