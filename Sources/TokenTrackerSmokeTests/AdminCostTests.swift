import Foundation
import TokenTrackerCore

/// Admin API cost collection: what each API is asked, how pages and failures come
/// back, and the schedule and cache that hold a reading between fetches. Mirrors
/// the admin cost section of windows/TokenTracker.Windows.Tests/Program.cs.
func runAdminCostTests() throws {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    let utc = TimeZone(identifier: "UTC")!
    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func dollars(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    // 14:00 on the 3rd in Seoul, whose month began at 15:00 UTC on October 31.
    let now = at("2026-11-03T05:00:00Z")
    let range = CostPeriod.requestRange(now: now, timeZone: seoul)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("token-tracker-admin-cost-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    expectEqual(
        AdminCostRequest.anthropicHourly(range: range, page: nil)?.absoluteString,
        "https://api.anthropic.com/v1/organizations/analytics/cost?starting_at=2026-10-31T15:00:00Z&ending_at=2026-11-03T05:00:00Z&time_bucket_width=1h&limit=1000",
        "Anthropic is asked for hourly buckets from the local 1st"
    )
    expectEqual(
        AdminCostRequest.anthropicByModel(range: range, page: "page_a+b/c")?.absoluteString,
        "https://api.anthropic.com/v1/organizations/analytics/cost?starting_at=2026-10-31T15:00:00Z&ending_at=2026-11-03T05:00:00Z&group_by%5B%5D=model&limit=100&page=page_a%2Bb%2Fc",
        "the model split names its group in brackets, and a cursor goes escaped"
    )
    expectEqual(
        AdminCostRequest.openAI(range: range, page: nil)?.absoluteString,
        "https://api.openai.com/v1/organization/costs?start_time=1793458800&end_time=1793682000&bucket_width=1d&group_by%5B%5D=line_item&limit=31",
        "OpenAI is asked for days by line item from the local 1st"
    )
    let firstHour = CostPeriod.requestRange(now: at("2026-11-01T00:40:00Z"), timeZone: utc)
    expect(AdminCostRequest.anthropicHourly(range: firstHour, page: nil) == nil, "the first hour of a month has nothing to ask Anthropic yet")
    expect(AdminCostRequest.openAI(range: firstHour, page: nil) != nil, "OpenAI takes any range that is not empty")
    let claudeHeaders = AdminCostRequest.headers(for: .claude, key: "sk-ant-admin01-key")
    expectEqual(claudeHeaders["x-api-key"], "sk-ant-admin01-key", "Anthropic takes the key in x-api-key")
    expectEqual(claudeHeaders["anthropic-beta"], "analytics-usage-cost-2026-08-24", "and the Analytics beta header")
    expectEqual(AdminCostRequest.headers(for: .codex, key: "sk-admin-key")["Authorization"], "Bearer sk-admin-key", "OpenAI takes a bearer token")

    expectEqual(AdminKeyText.suffix("sk-ant-admin01-abcdefgh1234"), "…1234", "a key shows its last four characters")
    expectEqual(AdminKeyText.suffix("short"), "…", "a key too short to be real shows nothing of itself")

    // Anthropic: hourly totals over two pages, then the model split.
    let anthropicFake = FakeHTTP([
        .init(status: 200, body: #"""
            {"data":[
              {"starting_at":"2026-11-01T03:00:00Z","ending_at":"2026-11-01T04:00:00Z","group":{},"cost":{"currency":"USD","amount":"250000.000000"}},
              {"starting_at":"2026-11-02T15:00:00Z","ending_at":"2026-11-02T16:00:00Z","group":{},"cost":{"currency":"USD","amount":"1234.500000"}}
            ],"has_more":true,"next_page":"page_2","data_refreshed_at":"2026-11-03T04:00:00Z"}
            """#),
        .init(status: 200, body: #"""
            {"data":[
              {"starting_at":"2026-11-03T01:00:00Z","ending_at":"2026-11-03T02:00:00Z","group":{},"cost":{"currency":"USD","amount":"100.000000"}}
            ],"has_more":false,"next_page":null,"data_refreshed_at":"2026-11-03T04:00:00Z"}
            """#),
        .init(status: 200, body: #"""
            {"data":[
              {"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-opus-5-5"},"cost":{"currency":"USD","amount":"200000.000000"}},
              {"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-sonnet-5-5"},"cost":{"currency":"USD","amount":"51334.500000"}},
              {"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":null},"cost":{"currency":"USD","amount":"0.000000"}},
              {"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-haiku-5-5"},"cost":{"currency":"USD","amount":"50.000000"}},
              {"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-fable-5-1"},"cost":{"currency":"USD","amount":"10.000000"}}
            ],"has_more":false,"next_page":null,"data_refreshed_at":"2026-11-03T04:00:00Z"}
            """#)
    ])
    let anthropic = AdminCostClient(
        provider: .claude,
        http: HTTPClient(transport: { try await anthropicFake.respond($0) }),
        rateLimitStore: RateLimitStore(url: directory.appendingPathComponent("claude-cost-rate-limit.json"))
    )
    let claudeResult = waitFor { await anthropic.fetch(key: "sk-ant-admin01-abcdefgh1234", now: now, timeZone: seoul) }
    guard case .cost(let claudeCost) = claudeResult else {
        expect(false, "Anthropic's month is read: \(claudeResult)")
        return
    }
    expectEqual(claudeCost.monthToDate?.value, dollars("2513.345"), "every page's hours add up to the month")
    expectEqual(claudeCost.today?.value, dollars("13.345"), "today is Seoul's, from its midnight")
    expectEqual(claudeCost.dataRefreshedAt, at("2026-11-03T04:00:00Z"), "the reading says how far the data reaches")
    expectEqual(claudeCost.topItems.map(\.name), ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"], "the three largest models")
    let anthropicRequests = waitFor { await anthropicFake.requests }
    expectEqual(anthropicRequests.count, 3, "two pages of hours and one of models")
    expect(anthropicRequests[1].url?.absoluteString.hasSuffix("&page=page_2") == true, "the second page carries the cursor")
    expectEqual(anthropicRequests[0].value(forHTTPHeaderField: "x-api-key"), "sk-ant-admin01-abcdefgh1234", "the key goes in its header")

    let untalliedFake = FakeHTTP([.init(status: 200, body: #"{"data":[],"has_more":false,"next_page":null,"data_refreshed_at":null}"#)])
    let untallied = AdminCostClient(
        provider: .claude,
        http: HTTPClient(transport: { try await untalliedFake.respond($0) }),
        rateLimitStore: RateLimitStore(url: directory.appendingPathComponent("untallied-rate-limit.json"))
    )
    let untalliedResult = waitFor { await untallied.fetch(key: "sk-ant-admin01-abcdefgh1234", now: now, timeZone: seoul) }
    guard case .cost(let untalliedCost) = untalliedResult else {
        expect(false, "an untallied month is still a reading: \(untalliedResult)")
        return
    }
    expect(untalliedCost.monthToDate == nil && untalliedCost.today == nil, "nothing tallied is no amount, not zero")
    expectEqual(waitFor { await untalliedFake.requests.count }, 1, "and leaves no model split to ask for")

    // OpenAI: days cut at Seoul's midnight, by line item.
    let openAIFake = FakeHTTP([
        .init(status: 200, body: #"""
            {"object":"page","data":[
              {"object":"bucket","start_time":1793458800,"end_time":1793545200,"results":[
                {"amount":{"value":1.25,"currency":"usd"},"line_item":"gpt-6, input"},
                {"amount":{"value":0.75,"currency":"usd"},"line_item":"gpt-6, output"}]},
              {"object":"bucket","start_time":1793631600,"end_time":1793718000,"results":[
                {"amount":{"value":0.5,"currency":"usd"},"line_item":"gpt-6, input"}]}
            ],"has_more":false,"next_page":null}
            """#),
        .init(status: 401, body: #"{"error":{"message":"Invalid API key"}}"#),
        .init(status: 429, body: "{}", headers: ["Retry-After": "30"])
    ])
    let openAI = AdminCostClient(
        provider: .codex,
        http: HTTPClient(transport: { try await openAIFake.respond($0) }),
        rateLimitStore: RateLimitStore(url: directory.appendingPathComponent("codex-cost-rate-limit.json"))
    )
    let codexResult = waitFor { await openAI.fetch(key: "sk-admin-abcdefgh5678", now: now, timeZone: seoul) }
    guard case .cost(let codexCost) = codexResult else {
        expect(false, "OpenAI's month is read: \(codexResult)")
        return
    }
    expectEqual(codexCost.monthToDate?.value, dollars("2.5"), "OpenAI's days add up to the month")
    expectEqual(codexCost.today?.value, dollars("0.5"), "and a day cut at local midnight is today")
    expect(codexCost.dataRefreshedAt == nil, "OpenAI has no watermark to report")
    expectEqual(codexCost.topItems.map(\.name), ["gpt-6"], "a model's line items add up under the model")
    expectEqual(codexCost.topItems.first?.amount.value, dollars("2.5"), "across every day")
    expectEqual(
        waitFor { await openAI.fetch(key: "sk-admin-abcdefgh5678", now: now, timeZone: seoul) },
        .failure(CostFetchFailure(kind: .keyRejected, message: "HTTP 401 from OpenAI Admin API")),
        "a 401 is a rejected key"
    )
    let limited = waitFor { await openAI.fetch(key: "sk-admin-abcdefgh5678", now: now, timeZone: seoul) }
    guard case .failure(let limitedFailure) = limited, limitedFailure.kind == .rateLimited else {
        expect(false, "a 429 is a rate limit: \(limited)")
        return
    }
    let again = waitFor { await openAI.fetch(key: "sk-admin-abcdefgh5678", now: now, timeZone: seoul) }
    guard case .failure(let againFailure) = again, againFailure.kind == .rateLimited else {
        expect(false, "the cooldown holds: \(again)")
        return
    }
    expectEqual(waitFor { await openAIFake.requests.count }, 3, "and is waited out without asking again")
    let otherKey = waitFor { await openAI.fetch(key: "sk-admin-otherkey9999", now: now, timeZone: seoul) }
    guard case .failure(let otherFailure) = otherKey, otherFailure.kind == .failed else {
        expect(false, "another key is not held to this key's cooldown: \(otherKey)")
        return
    }
    expectEqual(waitFor { await openAIFake.requests.count }, 4, "so it asks")

    // A reading holds for the rest of its local month; today, for the rest of its day.
    expectEqual(CostCachePolicy.usable(claudeCost, now: at("2026-11-03T14:59:00Z"), timeZone: seoul), claudeCost, "later the same Seoul day, all of it holds")
    let nextDay = CostCachePolicy.usable(claudeCost, now: at("2026-11-03T15:30:00Z"), timeZone: seoul)
    expect(nextDay?.today == nil && nextDay?.monthToDate == claudeCost.monthToDate, "the next day keeps the month but not today")
    expect(CostCachePolicy.usable(claudeCost, now: at("2026-11-30T15:30:00Z"), timeZone: seoul) == nil, "a new local month keeps nothing")

    // The service: a key is read only when switched on, fetches keep their own
    // schedule, and the last good reading carries through failures.
    let keys = MemoryAdminKeys()
    let cacheURL = directory.appendingPathComponent("cost-cache.json")
    let serviceFake = FakeHTTP([
        .init(status: 200, body: #"{"data":[{"starting_at":"2026-11-03T01:00:00Z","ending_at":"2026-11-03T02:00:00Z","group":{},"cost":{"currency":"USD","amount":"4200.000000"}}],"has_more":false,"data_refreshed_at":"2026-11-03T04:00:00Z"}"#),
        .init(status: 200, body: #"{"data":[{"starting_at":"2026-10-31T15:00:00Z","ending_at":"2026-11-03T05:00:00Z","group":{"model":"claude-opus-5-5"},"cost":{"currency":"USD","amount":"4200.000000"}}],"has_more":false,"data_refreshed_at":"2026-11-03T04:00:00Z"}"#),
        .init(status: 500, body: "{}"),
        .init(status: 401, body: "{}")
    ])
    func service(_ fake: FakeHTTP) -> AdminCostService {
        AdminCostService(
            keyStore: keys,
            clients: [.claude: AdminCostClient(
                provider: .claude,
                http: HTTPClient(transport: { try await fake.respond($0) }),
                rateLimitStore: RateLimitStore(url: directory.appendingPathComponent("service-rate-limit.json"))
            )],
            cacheStore: CostCacheStore(url: cacheURL)
        )
    }
    let costs = service(serviceFake)
    let off = waitFor { await costs.refreshIfDue(enabled: [:], now: now, timeZone: seoul) }
    expect(off[.claude]?.enabled == false && keys.reads == 0, "switched off, the key is never read")
    expectEqual(CostDiagnostics.lines(provider: .claude, state: off[.claude] ?? CostState()), ["Claude API cost: off"], "diagnostics says it is off")
    let noKey = waitFor { await costs.refreshIfDue(enabled: [.claude: true], now: now, timeZone: seoul) }
    expect(noKey[.claude]?.enabled == true && noKey[.claude]?.keySuffix == nil, "switched on without a key, there is nothing to fetch")
    expectEqual(CostDiagnostics.lines(provider: .claude, state: noKey[.claude]!), ["Claude API cost: on, no Admin key"], "diagnostics says the key is missing")
    expectEqual(waitFor { await serviceFake.requests.count }, 0, "so nothing is asked")

    keys.save("sk-ant-admin01-abcdefgh1234", for: .claude)
    let fetched = waitFor { await costs.refreshIfDue(enabled: [.claude: true], now: now, timeZone: seoul) }[.claude]!
    expectEqual(fetched.cost?.monthToDate?.value, dollars("42"), "with a key the month is fetched")
    expectEqual(fetched.nextFetchAt, now.addingTimeInterval(600), "and the next fetch waits ten minutes")
    expectEqual(
        CostDiagnostics.lines(provider: .claude, state: fetched),
        [
            "Claude API cost: on, key …1234",
            "Claude API cost month: $42.00",
            "Claude API cost today: $42.00",
            "Claude API cost complete up to: 2026-11-03T04:00:00Z",
            "Claude API cost top: claude-opus-5-5 $42.00",
            "Claude API cost measured: 2026-11-03T05:00:00Z",
            "Claude API cost last fetch: 2026-11-03T05:00:00Z ok"
        ],
        "diagnostics lists the reading, and never the key"
    )
    _ = waitFor { await costs.refreshIfDue(enabled: [.claude: true], now: now.addingTimeInterval(60), timeZone: seoul) }
    expectEqual(waitFor { await serviceFake.requests.count }, 2, "a fetch is not repeated before its turn")
    let failed = waitFor { await costs.refreshIfDue(enabled: [.claude: true], now: now.addingTimeInterval(601), timeZone: seoul) }[.claude]!
    expect(failed.failure?.kind == .failed && failed.isCached, "a failed fetch keeps the last reading, marked as cached")
    expectEqual(failed.cost?.monthToDate?.value, dollars("42"), "the reading is the last good one")
    expectEqual(failed.nextFetchAt, now.addingTimeInterval(901), "and is retried in five minutes")

    let relaunchFake = FakeHTTP([.init(status: 503, body: "{}")])
    let relaunchedCosts = service(relaunchFake)
    let relaunched = waitFor { await relaunchedCosts.refreshIfDue(enabled: [.claude: true], now: now.addingTimeInterval(700), timeZone: seoul) }[.claude]!
    expect(relaunched.isCached && relaunched.cost?.monthToDate?.value == dollars("42"), "a relaunch that cannot fetch shows the saved reading")

    keys.save("sk-ant-admin01-otherkey9999", for: .claude)
    let rejected = waitFor { await costs.refreshIfDue(enabled: [.claude: true], now: now.addingTimeInterval(602), timeZone: seoul) }[.claude]!
    expectEqual(waitFor { await serviceFake.requests.count }, 4, "a new key is fetched at once, whatever the schedule")
    expect(rejected.failure?.kind == .keyRejected && rejected.cost == nil, "and another key's reading is not passed off as its own")
    expectEqual(rejected.keySuffix, "…9999", "the new key is the one named")
}

/// What the API cost puts on screen: the card's lines, the menu bar's money, and
/// the rule that keeps a provider showing limits on its percentage. Mirrors the
/// cost display section of windows/TokenTracker.Windows.Tests/Program.cs.
func runCostDisplayTests() throws {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    func at(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func dollars(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    func usd(_ text: String) -> CostAmount { CostAmount(value: dollars(text)) }
    let english = Localizer(language: .english)
    let korean = Localizer(language: .korean)
    let now = at("2026-11-03T05:00:00Z")
    let cost = ProviderCost(
        provider: .claude,
        monthToDate: usd("2513.345"),
        today: usd("13.345"),
        topItems: [
            CostLineItem(name: "claude-opus-5-5", amount: usd("2000")),
            CostLineItem(name: "claude-sonnet-5-5", amount: usd("513.345")),
            CostLineItem(name: "claude-haiku-5-5", amount: usd("0.5"))
        ],
        dataRefreshedAt: at("2026-11-03T04:00:00Z"),
        measuredAt: now
    )
    func state(enabled: Bool = true, key: String? = "…1234", cost: ProviderCost? = nil, failure: CostFetchFailure? = nil) -> CostState {
        var state = CostState()
        state.enabled = enabled
        state.keySuffix = key
        state.cost = cost
        state.failure = failure
        return state
    }

    expect(AdminCostText.view(state: state(enabled: false, cost: cost), budget: 0, now: now, timeZone: seoul, localizer: korean) == nil, "switched off, there is no cost to show")
    expect(AdminCostText.view(state: state(key: nil), budget: 0, now: now, timeZone: seoul, localizer: korean) == nil, "and without a key, neither")

    let loading = AdminCostText.view(state: state(), budget: 100, now: now, timeZone: seoul, localizer: korean)!
    expectEqual(loading.status, .loading, "switched on with a key and no answer yet is loading")
    expectEqual(loading.statusTitle, "불러오는 중", "in the user's language")
    expect(loading.monthValue == "--" && loading.detail == nil && loading.budgetText == nil && loading.asOf == nil, "with nothing to show yet")

    let ok = AdminCostText.view(state: state(cost: cost), budget: 5000, now: now, timeZone: seoul, localizer: korean)!
    expectEqual(ok.status, .ok, "a fresh reading is fine")
    expectEqual(ok.statusTitle, "정상", "and says so")
    expectEqual(ok.monthLabel, "이번 달 사용", "the month is this month's use")
    expectEqual(ok.monthValue, "$2.5K", "in the cost format")
    expectEqual(ok.budgetPercent, 50, "against the budget, rounded down")
    expectEqual(ok.budgetText, "예산 $5.0K 중 50%", "the budget line names the budget")
    expect(!ok.isBudgetWarning, "half a budget is no warning")
    expectEqual(ok.detail, "오늘 $13.35 · Opus 5.5 79% · Sonnet 5.5 20%", "today, then the two largest models' shares")
    expectEqual(ok.asOf, "13:00 기준", "and how far the data reaches, in Seoul's time")

    let english84 = AdminCostText.view(state: state(cost: cost), budget: 3000, now: now, timeZone: seoul, localizer: english)!
    expectEqual(english84.budgetText, "83% of $3.0K budget", "the budget line in English")
    expect(english84.isBudgetWarning, "80% of a budget is a warning")
    let yesterday = ProviderCost(provider: .claude, monthToDate: cost.monthToDate, today: nil, topItems: [], dataRefreshedAt: at("2026-11-02T13:10:00Z"), measuredAt: now)
    let lagging = AdminCostText.view(state: state(cost: yesterday), budget: 0, now: now, timeZone: seoul, localizer: english)!
    expectEqual(lagging.asOf, "as of Nov 2 22:10", "data from another day names the day")
    expectEqual(lagging.detail, "Today not tallied yet", "and today is not tallied, not zero")
    expectEqual(AdminCostText.view(state: state(cost: yesterday), budget: 0, now: now, timeZone: seoul, localizer: korean)?.asOf, "11월 2일 22:10 기준", "in Korean too")
    let untallied = ProviderCost(provider: .claude, monthToDate: nil, today: nil, topItems: [], dataRefreshedAt: nil, measuredAt: now)
    let empty = AdminCostText.view(state: state(cost: untallied), budget: 100, now: now, timeZone: seoul, localizer: korean)!
    expect(empty.monthValue == "집계 전" && empty.detail == nil && empty.budgetPercent == nil, "an untallied month shows no amount and no bar")

    let failedFetch = CostFetchFailure(kind: .failed, message: "HTTP 500 from Anthropic Admin API")
    let cached = AdminCostText.view(state: state(cost: cost, failure: failedFetch), budget: 0, now: now, timeZone: seoul, localizer: korean)!
    expect(cached.status == .cached && cached.statusTitle == "캐시 데이터 사용 중", "a failed fetch over a reading is the cache")
    expectEqual(cached.failureMessage, "HTTP 500 from Anthropic Admin API", "and keeps why for a tooltip")
    let rejected = CostFetchFailure(kind: .keyRejected, message: "HTTP 401 from Anthropic Admin API")
    expectEqual(AdminCostText.view(state: state(cost: cost, failure: rejected), budget: 0, now: now, timeZone: seoul, localizer: korean)?.status, .keyRejected, "a rejected key outranks the cache")
    expectEqual(AdminCostText.view(state: state(failure: rejected), budget: 0, now: now, timeZone: seoul, localizer: korean)?.statusTitle, "Admin 키 거부됨", "and is named")
    expectEqual(AdminCostText.view(state: state(failure: CostFetchFailure(kind: .rateLimited, message: "HTTP 429")), budget: 0, now: now, timeZone: seoul, localizer: korean)?.status, .rateLimited, "a rate limit with no reading")
    expectEqual(AdminCostText.view(state: state(failure: failedFetch), budget: 0, now: now, timeZone: seoul, localizer: korean)?.statusTitle, "비용을 가져오지 못함", "any other failure with no reading")

    expectEqual(CostItemName.display("claude-opus-5-5"), "Opus 5.5", "a model reads as family and version")
    expectEqual(CostItemName.display("claude-sonnet-4-5-20250929"), "Sonnet 4.5", "without its date stamp")
    expectEqual(CostItemName.display("claude-3-5-haiku-20241022"), "Haiku 3.5", "whichever order the version comes in")
    expectEqual(CostItemName.display("gpt-6"), "gpt-6", "other names stay as they are")
    expectEqual(CostItemName.lineItemGroup("gpt-6, input"), "gpt-6", "an OpenAI line item belongs to its model")
    expectEqual(CostItemName.lineItemGroup("web search"), "web search", "one with no model stays whole")

    expectEqual(CostFormatter.compact(usd("42.18")), "$42", "the menu bar drops cents from $10")
    expectEqual(CostFormatter.compact(usd("42.5")), "$43", "rounding half away from zero")
    expectEqual(CostFormatter.compact(usd("3.07")), "$3.07", "but keeps them below, so a small spend is not $0")
    expectEqual(CostFormatter.compact(usd("1234")), "$1.2K", "and shortens thousands")

    expect(AdminKeyText.looksLikeAdminKey("sk-ant-admin01-abcdefgh", for: .claude), "an Anthropic Admin key")
    expect(!AdminKeyText.looksLikeAdminKey("sk-ant-api03-abcdefgh", for: .claude), "an ordinary Anthropic API key cannot read cost")
    expect(AdminKeyText.looksLikeAdminKey(" sk-admin-abcdefgh\n", for: .codex), "an OpenAI Admin key, pasted with whitespace")
    expect(!AdminKeyText.looksLikeAdminKey("sk-proj-abcdefgh", for: .codex), "an OpenAI project key cannot read cost")

    // The menu bar: only a provider tracked by API cost alone shows money.
    let small = ProviderCost(provider: .claude, monthToDate: usd("42.18"), today: nil, topItems: [], dataRefreshedAt: nil, measuredAt: now)
    let states: [Provider: CostState] = [.claude: state(cost: small), .codex: state(cost: small)]
    let entries = CostMenuBar.entries(subscriptionShown: [.claude: false, .codex: true], states: states, budgets: [.claude: 50])
    expectEqual(entries, [.claude: MenuBarCost(text: "$42", isWarning: true)], "Claude shows its spend, past 80% of its budget; Codex keeps its percentage")
    expectEqual(
        CostMenuBar.entries(subscriptionShown: [.claude: false, .codex: false], states: [.claude: state()], budgets: [:]),
        [.claude: MenuBarCost(text: "--", isWarning: false)],
        "before the first reading the spend is a placeholder"
    )
    expect(CostMenuBar.entries(subscriptionShown: [.claude: false], states: [.claude: state(key: nil)], budgets: [:]).isEmpty, "no key, no money in the menu bar")
    expect(!CostMenuBar.trayShowsDollar(subscriptionShown: [.claude: false, .codex: true], entries: entries), "the tray keeps a percentage while any limit is shown")
    expect(CostMenuBar.trayShowsDollar(subscriptionShown: [.claude: false, .codex: false], entries: entries), "and draws $ when only money is left")
    expect(!CostMenuBar.trayShowsDollar(subscriptionShown: [.claude: false, .codex: false], entries: [:]), "but not with nothing to show")

    let snapshot = UsageSnapshot(
        claude: .unavailable(.claude, error: "Disabled"),
        codex: ProviderUsage(provider: .codex, remainingPercent5h: nil, remainingPercent7d: 91, resetAt5h: nil, resetAt7d: nil, source: .api, error: nil, plan: "plus", model: nil, updatedAt: now),
        updatedAt: now
    )
    let claudeSpend: [Provider: MenuBarCost] = [.claude: MenuBarCost(text: "$42", isWarning: false)]
    expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .both, costs: claudeSpend), "Cdx 91% · Cl $42", "both: Codex's percentage beside Claude's spend")
    expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .claudeOnly, costs: claudeSpend), "Cl $42", "Claude alone")
    expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .claudeOnly, labelStyle: .icon, costs: claudeSpend), "Claude $42", "with the logo label")
    expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .lowestRemaining, costs: claudeSpend), "AI 91%", "the lowest-remaining mode keeps its percentage")
    let noLimits = UsageSnapshot(claude: .unavailable(.claude, error: "Disabled"), codex: .unavailable(.codex, error: "Disabled"), updatedAt: now)
    let bothSpend: [Provider: MenuBarCost] = [.claude: MenuBarCost(text: "$42", isWarning: false), .codex: MenuBarCost(text: "$8.00", isWarning: false)]
    expectEqual(DisplayFormatter.statusTitle(snapshot: noLimits, mode: .lowestRemaining, costs: bothSpend), "Cl $42 · Cdx $8.00", "and lists the spend when no provider has a percentage")
    expectEqual(DisplayFormatter.statusTitle(snapshot: snapshot, mode: .both), "Cdx 91% · Cl --", "without costs the title is as it was")
}

/// Answers each request with the next queued reply, and keeps what was asked.
private actor FakeHTTP {
    struct Reply {
        let status: Int
        let body: String
        var headers: [String: String] = [:]
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.cannotConnectToHost) }
        let reply = replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

/// The keychain stand-in. Counts reads, so a test can tell the key was never touched.
private final class MemoryAdminKeys: AdminKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [Provider: String] = [:]
    private var readCount = 0

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return readCount
    }

    func key(for provider: Provider) -> String? {
        lock.lock()
        defer { lock.unlock() }
        readCount += 1
        return keys[provider]
    }

    @discardableResult
    func save(_ key: String, for provider: Provider) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        keys[provider] = key
        return true
    }

    func delete(for provider: Provider) {
        lock.lock()
        defer { lock.unlock() }
        keys[provider] = nil
    }
}
