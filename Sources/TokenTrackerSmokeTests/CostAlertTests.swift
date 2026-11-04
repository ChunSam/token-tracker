import Foundation
import TokenTrackerCore

/// Money alerts: a budget threshold once per local month, Claude extra usage leaving
/// `normal`, Codex reaching its credit overage limit, and nothing at all for an
/// account that does not pay this way. Mirrors RunCostAlertTests in
/// windows/TokenTracker.Windows.Tests/Program.cs.
func runCostAlertTests() throws {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func usd(_ text: String) -> CostAmount { CostAmount(value: Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!) }
    func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }
    let korean = Localizer(language: .korean)
    let english = Localizer(language: .english)
    // 14:00 on November 3rd in Seoul.
    let now = at("2026-11-03T05:00:00Z")
    func costState(_ month: String?, key: String? = "…1234") -> CostState {
        var state = CostState()
        state.enabled = true
        state.keySuffix = key
        state.cost = ProviderCost(provider: .claude, monthToDate: month.map(usd), today: nil, topItems: [], dataRefreshedAt: nil, measuredAt: now)
        return state
    }
    func evaluate(
        _ costs: [Provider: CostState],
        budget: Int = 100,
        snapshot: UsageSnapshot? = nil,
        delivered: Set<String> = [],
        notifications: Bool = true,
        at time: Date? = nil,
        localizer: Localizer? = nil
    ) -> CostAlertResult {
        CostAlertEvaluator.evaluate(
            snapshot: snapshot,
            costs: costs,
            budgets: [.claude: budget],
            delivered: delivered,
            notificationsEnabled: notifications,
            now: time ?? now,
            timeZone: seoul,
            localizer: localizer ?? korean
        )
    }

    let at84 = evaluate([.claude: costState("84.2")])
    expectEqual(at84.alerts.map(\.id), ["claude-cost-80-2026-11"], "84% of a budget is its 80% alert")
    expectEqual(at84.alerts.first?.title, "API 비용 예산", "titled in the user's language")
    expectEqual(at84.alerts.first?.body, "Anthropic API: 이번 달 $84.20, 예산 $100의 84%", "naming the organization, the month's spend and the budget")
    expectEqual(at84.delivered, ["claude-cost-80-2026-11"], "and remembered")
    expect(evaluate([.claude: costState("90")], delivered: at84.delivered).alerts.isEmpty, "the same threshold is not said twice in a month")
    let at105 = evaluate([.claude: costState("105")], delivered: at84.delivered)
    expectEqual(at105.alerts.map(\.id), ["claude-cost-100-2026-11"], "reaching the budget is news after 80%")
    let jump = evaluate([.claude: costState("105")])
    expectEqual(jump.alerts.map(\.id), ["claude-cost-100-2026-11"], "a jump past both thresholds says only 100%")
    expectEqual(jump.delivered, ["claude-cost-80-2026-11", "claude-cost-100-2026-11"], "and counts 80% as said")
    expectEqual(
        evaluate([.claude: costState("84.2")], localizer: english).alerts.first?.body,
        "Anthropic API: $84.20 this month, 84% of the $100 budget",
        "the body in English"
    )
    expect(evaluate([.claude: costState("79.99")]).alerts.isEmpty, "under 80% is no alert")
    expect(evaluate([.claude: costState("500")], budget: 0).alerts.isEmpty, "a zero budget is off")
    expect(evaluate([.claude: costState("500", key: nil)]).alerts.isEmpty, "no key, no money, no alert")
    expect(evaluate([.claude: costState(nil)]).alerts.isEmpty, "an untallied month has nothing to say")
    let off = evaluate([.claude: costState("105")], delivered: ["claude-cost-80-2026-11"], notifications: false)
    expect(off.alerts.isEmpty, "notifications off sends nothing")
    expectEqual(off.delivered, ["claude-cost-80-2026-11"], "and records nothing new, so turning them on still says 100%")
    let december = evaluate([:], delivered: ["claude-cost-100-2026-11"], at: at("2026-11-30T15:30:00Z"))
    expect(december.delivered.isEmpty, "a new local month forgets the last one's alerts")

    // Stage 1: the money the subscription responses carry.
    func claude(_ spend: String) -> ProviderUsage {
        try! ClaudeUsageParser.parse(json(#"{"five_hour":{"utilization":20},"spend":"# + spend + "}"), updatedAt: now)
    }
    let codexPlus = CodexUsageParser.parse(object: json(#"""
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000,"reset_at":1793700000}},
         "credits":{"has_credits":false,"unlimited":false,"overage_limit_reached":false,"balance":"0"}}
        """#), updatedAt: now)!
    func snapshot(claude: ProviderUsage, codex: ProviderUsage = codexPlus) -> UsageSnapshot {
        UsageSnapshot(claude: claude, codex: codex, updatedAt: now)
    }
    let warning = claude(#"{"enabled":true,"used":{"amount_minor":410,"currency":"USD","exponent":2},"limit":{"amount_minor":500,"currency":"USD","exponent":2},"severity":"Warning"}"#)
    let extra = evaluate([:], snapshot: snapshot(claude: warning))
    expectEqual(extra.alerts.map(\.id), ["claude-extra-warning-2026-11"], "extra usage leaving normal is an alert")
    expectEqual(extra.alerts.first?.title, "Claude 추가 사용량", "about Claude's extra usage")
    expectEqual(extra.alerts.first?.body, "추가 사용량이 $4.10 / $5.00입니다.", "with spend against the limit")
    expect(evaluate([:], snapshot: snapshot(claude: warning), delivered: extra.delivered).alerts.isEmpty, "said once a month")
    let normal = claude(#"{"enabled":true,"used":{"amount_minor":100,"currency":"USD","exponent":2},"severity":"normal"}"#)
    expect(evaluate([:], snapshot: snapshot(claude: normal)).alerts.isEmpty, "normal is no news")
    let pro = claude(#"{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"warning","enabled":false}"#)
    expect(evaluate([:], snapshot: snapshot(claude: pro)).alerts.isEmpty, "with extra usage off there is no alert, whatever the severity")

    expect(codexPlus.creditLimitReached == nil, "the measured Plus response has no credit limit to reach")
    let limited = CodexUsageParser.parse(object: json(#"""
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000,"reset_at":1793700000}},
         "credits":{"has_credits":true,"overage_limit_reached":true,"balance":"0"}}
        """#), updatedAt: now)!
    expectEqual(limited.creditLimitReached, true, "an account holding credits can reach their overage limit")
    let credits = evaluate([:], snapshot: snapshot(claude: pro, codex: limited))
    expectEqual(credits.alerts.map(\.id), ["codex-credits-limit-2026-11"], "which is an alert")
    expectEqual(credits.alerts.first?.body, "Codex 크레딧 초과 사용 한도에 도달했습니다.", "saying so")
    let noCredits = CodexUsageParser.parse(object: json(#"""
        {"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000,"reset_at":1793700000}},
         "credits":{"has_credits":false,"overage_limit_reached":true,"balance":"0"}}
        """#), updatedAt: now)!
    expect(noCredits.creditLimitReached == nil, "an account without credits is never told about a credit limit")
    let recorded = UsageHistoryPolicy.measurementsOnly(snapshot(claude: pro, codex: limited))
    expect(recorded.codex.creditLimitReached == nil, "history keeps no money flags")
}
