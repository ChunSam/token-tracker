import Foundation
import TokenTrackerCore

/// Money display: local-time boundaries in several zones, both Admin API parsers,
/// the subscription fields, and the rule that keeps money off a subscription-only
/// user's screen. Mirrors the cost section of windows/TokenTracker.Windows.Tests/Program.cs.
func runCostTests() throws {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    let newYork = TimeZone(identifier: "America/New_York")!
    let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    let utc = TimeZone(identifier: "UTC")!
    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }
    func dollars(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }

    // Boundaries follow the zone the device is in, whichever it is.
    let now = at("2026-11-03T05:00:00Z")
    expectEqual(CostPeriod.dayStart(now: now, timeZone: seoul), at("2026-11-02T15:00:00Z"), "Seoul's day starts at its own midnight")
    expectEqual(CostPeriod.monthStart(now: now, timeZone: seoul), at("2026-10-31T15:00:00Z"), "Seoul's month starts at its own midnight on the 1st")
    expectEqual(CostPeriod.dayStart(now: now, timeZone: newYork), at("2026-11-03T05:00:00Z"), "an instant exactly at local midnight starts that day")
    expectEqual(CostPeriod.monthStart(now: now, timeZone: newYork), at("2026-11-01T04:00:00Z"), "New York's month started under daylight time")
    expectEqual(CostPeriod.dayStart(now: now, timeZone: kolkata), at("2026-11-02T18:30:00Z"), "a half-hour zone keeps its half hour")
    expectEqual(CostPeriod.dayStart(now: now, timeZone: utc), at("2026-11-03T00:00:00Z"), "UTC is one zone among others")
    expectEqual(
        CostPeriod.dayStart(now: at("2026-11-02T12:00:00Z"), timeZone: newYork)
            .timeIntervalSince(CostPeriod.dayStart(now: at("2026-11-01T12:00:00Z"), timeZone: newYork)),
        TimeInterval(25 * 3600),
        "the day daylight time ends has 25 hours"
    )
    expectEqual(
        CostPeriod.dayStart(now: at("2026-03-09T12:00:00Z"), timeZone: newYork)
            .timeIntervalSince(CostPeriod.dayStart(now: at("2026-03-08T12:00:00Z"), timeZone: newYork)),
        TimeInterval(23 * 3600),
        "the day daylight time starts has 23 hours"
    )
    expectEqual(CostPeriod.monthKey(now: at("2026-11-30T16:00:00Z"), timeZone: seoul), "2026-12", "Seoul is already in December")
    expectEqual(CostPeriod.monthKey(now: at("2026-11-30T16:00:00Z"), timeZone: utc), "2026-11", "UTC is still in November")
    expectEqual(CostPeriod.requestRange(now: now, timeZone: seoul).start, at("2026-10-31T15:00:00Z"), "a fetch asks from the local 1st")

    // Anthropic Analytics: hourly buckets, cents as decimal strings.
    func anthropicHourly(hours: Int, from start: String, cents: String, lastCents: String, refreshed: String?) -> [String: Any] {
        let first = at(start)
        var rows: [[String: Any]] = []
        for hour in 0..<hours {
            // Typed pieces rather than one nested literal: heterogeneous literals
            // are slow to type-check on CI's compiler.
            let begin = first.addingTimeInterval(TimeInterval(hour * 3600))
            let amount: String = hour == hours - 1 ? lastCents : cents
            let cost: [String: Any] = ["currency": "USD", "amount": amount, "list_amount": cents, "requests": 3]
            let group: [String: Any] = ["model": NSNull()]
            let row: [String: Any] = [
                "starting_at": ISO8601DateFormatter().string(from: begin),
                "ending_at": ISO8601DateFormatter().string(from: begin.addingTimeInterval(3600)),
                "group": group,
                "cost": cost
            ]
            rows.append(row)
        }
        var page: [String: Any] = ["data": rows, "has_more": false, "next_page": NSNull()]
        page["data_refreshed_at"] = refreshed.map { $0 as Any } ?? NSNull()
        return page
    }
    let hourly = AnthropicCostParser.page(anthropicHourly(hours: 16, from: "2026-11-02T13:00:00Z", cents: "100.000000", lastCents: "33.333333", refreshed: "2026-11-03T04:30:00Z"))!
    expectEqual(hourly.buckets.count, 16, "every hourly row becomes a bucket")
    expectEqual(hourly.freshness, .refreshedAt(at("2026-11-03T04:30:00Z")), "the refresh time is kept")
    expect(hourly.nextPage == nil, "a last page has no next page")
    let seoulReport = CostAggregator.report(buckets: hourly.buckets, freshness: hourly.freshness, now: now, timeZone: seoul)
    expectEqual(seoulReport.monthToDate?.value, dollars("15.33333333"), "cents add up exactly across the month")
    expectEqual(seoulReport.today?.value, dollars("13.33333333"), "Seoul's today starts at 15:00 UTC")
    let utcReport = CostAggregator.report(buckets: hourly.buckets, freshness: hourly.freshness, now: now, timeZone: utc)
    expectEqual(utcReport.today?.value, dollars("4.33333333"), "UTC's today starts at 00:00 UTC")
    let kolkataReport = CostAggregator.report(buckets: hourly.buckets, freshness: hourly.freshness, now: now, timeZone: kolkata)
    expectEqual(kolkataReport.today?.value, dollars("10.33333333"), "a half-hour zone takes the hour it starts in")
    let stale = CostAggregator.report(buckets: hourly.buckets, freshness: .refreshedAt(at("2026-11-02T14:00:00Z")), now: now, timeZone: seoul)
    expect(stale.today == nil, "a day the data has not reached yet is not tallied, not zero")
    expectEqual(stale.monthToDate?.value, dollars("15.33333333"), "the month still adds up what there is")
    let empty = AnthropicCostParser.page(json(#"{"data":[],"has_more":false,"next_page":null,"data_refreshed_at":null}"#))!
    expectEqual(empty.freshness, .notTallied, "no refresh time means nothing is tallied")
    let untallied = CostAggregator.report(buckets: empty.buckets, freshness: empty.freshness, now: now, timeZone: seoul)
    expect(untallied.monthToDate == nil && untallied.today == nil, "nothing tallied shows no amounts at all")

    var tiny: [[String: Any]] = []
    for hour in 0..<744 {
        let begin = at("2026-10-01T00:00:00Z").addingTimeInterval(TimeInterval(hour * 3600))
        let cost: [String: Any] = ["currency": "USD", "amount": "0.100000"]
        let row: [String: Any] = [
            "starting_at": ISO8601DateFormatter().string(from: begin),
            "ending_at": ISO8601DateFormatter().string(from: begin.addingTimeInterval(3600)),
            "cost": cost
        ]
        tiny.append(row)
    }
    let tinyJSON: [String: Any] = ["data": tiny, "has_more": false, "data_refreshed_at": "2026-11-01T00:00:00Z"]
    let tinyPage = AnthropicCostParser.page(tinyJSON)!
    let tinyReport = CostAggregator.report(buckets: tinyPage.buckets, freshness: tinyPage.freshness, now: at("2026-10-31T23:59:59Z"), timeZone: utc)
    expectEqual(tinyReport.monthToDate?.value, dollars("0.744"), "744 tenths of a cent add up to exactly $0.744")

    let models = AnthropicCostParser.page(json(#"""
        {"data":[
          {"starting_at":"2026-11-01T00:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-sonnet-5-5"},"cost":{"currency":"USD","amount":"412.500000"}},
          {"starting_at":"2026-11-01T00:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-opus-5-5"},"cost":{"currency":"USD","amount":"1120.000000"}},
          {"starting_at":"2026-11-01T00:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":null},"cost":{"currency":"USD","amount":"12.000000"}}
        ],"has_more":true,"next_page":"page_2","data_refreshed_at":"2026-11-03T04:30:00Z"}
        """#))!
    expectEqual(models.nextPage, "page_2", "a page with more says where to go next")
    expectEqual(CostLineItem.top(models.items).map(\.name), ["claude-opus-5-5", "claude-sonnet-5-5"], "models rank by spend; a row with no model is not one")
    expectEqual(CostLineItem.top(models.items).first?.amount.value, dollars("11.2"), "a model's cents become dollars")
    expect(AnthropicCostParser.page(json(#"{"error":{"type":"permission_error"}}"#)) == nil, "an error body is not a page")

    // OpenAI: day buckets in dollars, under "results" or "result".
    let utcDays = OpenAICostParser.page(json(#"""
        {"object":"page","data":[
          {"object":"bucket","start_time":1793404800,"end_time":1793491200,"results":[{"object":"organization.costs.result","amount":{"value":5.0,"currency":"usd"},"line_item":"gpt-6, input"}]},
          {"object":"bucket","start_time":1793491200,"end_time":1793577600,"results":[{"amount":{"value":1.1,"currency":"usd"},"line_item":"gpt-6, input"},{"amount":{"value":0.06,"currency":"usd"},"line_item":"web search"}]},
          {"object":"bucket","start_time":1793577600,"end_time":1793664000,"result":[{"amount":{"value":2.2,"currency":"usd"},"line_item":"gpt-6, output"}]},
          {"object":"bucket","start_time":1793664000,"end_time":1793750400,"results":[{"amount":{"value":0.3,"currency":"usd"},"line_item":"gpt-6, output"}]}
        ],"has_more":false,"next_page":null}
        """#))!
    expectEqual(utcDays.buckets.count, 4, "every day bucket is read, whichever name its list has")
    expectEqual(utcDays.buckets[1].amount, CostAmount(value: dollars("1.16"), currency: "USD"), "a bucket's results add up, in upper-case currency")
    let openAIInSeoul = CostAggregator.report(buckets: utcDays.buckets, freshness: utcDays.freshness, now: now, timeZone: seoul)
    expect(openAIInSeoul.today == nil, "a UTC day bucket cannot say what Seoul spent today")
    expectEqual(openAIInSeoul.monthToDate?.value, dollars("8.66"), "the month counts every bucket that reaches into it")
    let openAIInUTC = CostAggregator.report(buckets: utcDays.buckets, freshness: utcDays.freshness, now: now, timeZone: utc)
    expectEqual(openAIInUTC.today?.value, dollars("0.3"), "UTC day buckets give UTC its today")
    expectEqual(openAIInUTC.monthToDate?.value, dollars("3.66"), "a bucket that ends where the month starts is last month's")
    let localDays = OpenAICostParser.page(json(#"""
        {"data":[
          {"start_time":1793458800,"end_time":1793545200,"results":[{"amount":{"value":1.0,"currency":"usd"}}]},
          {"start_time":1793545200,"end_time":1793631600,"results":[{"amount":{"value":2.0,"currency":"usd"}}]},
          {"start_time":1793631600,"end_time":1793718000,"results":[{"amount":{"value":0.25,"currency":"usd"}}]}
        ],"has_more":false}
        """#))!
    let openAILocal = CostAggregator.report(buckets: localDays.buckets, freshness: localDays.freshness, now: now, timeZone: seoul)
    expectEqual(openAILocal.today?.value, dollars("0.25"), "buckets cut at Seoul's midnight give Seoul its today")
    expectEqual(openAILocal.monthToDate?.value, dollars("3.25"), "and its month")
    expectEqual(CostLineItem.top(utcDays.items).map(\.name), ["gpt-6, input", "gpt-6, output", "web search"], "line items merge across buckets")

    // Subscription money appears only for accounts that pay it.
    let proAccount = json(#"""
        {"extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"utilization":null,"currency":null,"decimal_places":null,"user_disabled":true},
         "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"severity":"normal","enabled":false}}
        """#)
    expect(SubscriptionCostParser.claudeExtraUsage(proAccount) == nil, "a subscription with extra usage off shows no money")
    let extraOn = SubscriptionCostParser.claudeExtraUsage(json(#"""
        {"spend":{"enabled":true,"used":{"amount_minor":186,"currency":"USD","exponent":2},"limit":{"amount_minor":500,"currency":"USD","exponent":2},"severity":"normal"}}
        """#))
    expectEqual(extraOn?.used.value, dollars("1.86"), "spend states its unit: 186 minor units at exponent 2")
    expectEqual(extraOn?.limit?.value, dollars("5"), "the limit reads the same way")
    expect(SubscriptionCostParser.claudeExtraUsage(json(#"{"extra_usage":{"is_enabled":true,"used_credits":186}}"#)) == nil, "extra usage without a spend amount is not guessed at")
    expect(SubscriptionCostParser.claudeExtraUsage(json(#"{"spend":{"enabled":true,"used":{"amount_minor":5,"currency":"USD","exponent":9}}}"#)) == nil, "an implausible exponent reads as off")
    expect(SubscriptionCostParser.claudeExtraUsage(json(#"{"five_hour":{"utilization":10}}"#)) == nil, "no spend fields at all reads as off")
    expect(SubscriptionCostParser.codexCredits(json(#"{"credits":{"has_credits":false,"balance":"0"}}"#)) == nil, "no credits shows nothing")
    expectEqual(SubscriptionCostParser.codexCredits(json(#"{"credits":{"has_credits":true,"balance":"18.40"}}"#)), dollars("18.4"), "a credit balance reads exactly")
    expect(SubscriptionCostParser.codexCredits(json(#"{"credits":{"has_credits":true,"balance":"lots"}}"#)) == nil, "a balance that is not a number shows nothing")

    expect(!CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: false, hasAdminKey: false), "a subscription-only user sees no money")
    expect(CostVisibility.shows(subscriptionExtra: true, apiCostEnabled: false, hasAdminKey: false), "extra usage on shows money")
    expect(!CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: true, hasAdminKey: false), "API cost needs a key")
    expect(!CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: false, hasAdminKey: true), "a stored key alone does not switch it on")
    expect(CostVisibility.shows(subscriptionExtra: false, apiCostEnabled: true, hasAdminKey: true), "API cost with a key shows money")
    expect(!CostVisibility.menuBarShowsCost(subscriptionLimitsShown: true, apiCostShown: true), "the menu bar keeps percentages while limits are shown")
    expect(CostVisibility.menuBarShowsCost(subscriptionLimitsShown: false, apiCostShown: true), "an API-only provider puts its spend in the menu bar")
    expect(!CostVisibility.menuBarShowsCost(subscriptionLimitsShown: false, apiCostShown: false), "nothing to show is nothing shown")

    func usd(_ text: String) -> String { CostFormatter.text(CostAmount(value: dollars(text))) }
    expectEqual(usd("0"), "$0.00", "zero is two places")
    expectEqual(usd("0.004"), "<$0.01", "under a cent is not zero")
    expectEqual(usd("12.345"), "$12.35", "halves round away from zero")
    expectEqual(usd("999.99"), "$999.99", "under a thousand stays in cents")
    expectEqual(usd("1234.5"), "$1.2K", "thousands shorten")
    expectEqual(usd("1250"), "$1.3K", "and round away from zero")
    expectEqual(usd("3400000"), "$3.4M", "millions shorten")
    expectEqual(usd("-2.5"), "-$2.50", "a refund keeps its sign")
    expectEqual(CostFormatter.text(CostAmount(value: dollars("12.3"), currency: "eur")), "12.30 EUR", "another currency is named")
    expectEqual(CostFormatter.credits(dollars("18.4")), "18.40", "credits are a number, not dollars")

    expectEqual(CostBudget.percent(spent: dollars("79.99"), budget: 100), 79, "percent rounds down")
    expectEqual(CostBudget.reachedThresholds(spent: 80, budget: 100), [80], "80% reached")
    expectEqual(CostBudget.reachedThresholds(spent: 100, budget: 100), [80, 100], "100% reached")
    expectEqual(CostBudget.reachedThresholds(spent: 150, budget: 100), [80, 100], "past the budget still reports both")
    expect(CostBudget.percent(spent: 50, budget: 0) == nil && CostBudget.reachedThresholds(spent: 50, budget: 0).isEmpty, "a zero budget is off")
    expectEqual(CostBudget.alertID(provider: .claude, threshold: 80, now: at("2026-11-30T16:00:00Z"), timeZone: seoul), "claude-cost-80-2026-12", "an alert belongs to the local month")
    expectEqual(CostBudget.alertID(provider: .codex, threshold: 100, now: at("2026-11-30T16:00:00Z"), timeZone: utc), "codex-cost-100-2026-11", "which depends on the zone")

    expectEqual(CostFetchPolicy.nextFetch(after: now, succeeded: true), now.addingTimeInterval(600), "a good fetch waits ten minutes")
    expectEqual(CostFetchPolicy.nextFetch(after: now, succeeded: false), now.addingTimeInterval(300), "a failed fetch is retried in five")
    expect(CostFetchPolicy.isDue(nextFetchAt: nil, now: now), "the first fetch is due at once")
    expect(!CostFetchPolicy.isDue(nextFetchAt: now.addingTimeInterval(1), now: now), "a fetch is not due early")
    expect(CostFetchPolicy.isDue(nextFetchAt: now, now: now), "a fetch is due on time")
}
