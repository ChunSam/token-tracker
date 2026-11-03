# 금액 표시 설계 (Claude · Codex)

상태: 설계 초안 (2026-11-03). 구현 전 검토용이다.

## 왜 필요한가

Token Tracker는 구독 플랜의 5시간·7일 한도만 보여준다. API를 쓴 만큼 돈을 내는 사용자는 Claude Code나
Codex에 API 키로 로그인하므로, 앱이 읽는 구독용 OAuth 토큰이 없고 카드에는 `로그인 필요`와 `--`만 남는다.
이 사용자에게 필요한 것은 "이번 달 얼마 나왔나"다. 구독 사용자도 한도를 넘겨 쓰는 추가 사용량(Claude)이나
크레딧(Codex)은 금액이라 지금 화면에는 나오지 않는다.

## 범위

| 단계 | 대상 | 데이터 | 새 자격 증명 |
|---|---|---|---|
| 1 | 구독 사용자 | Claude 추가 사용량, Codex 크레딧 잔액 | 없음 (지금 읽는 토큰 그대로) |
| 2 | API 사용자 | Claude·OpenAI 조직의 실제 청구 비용 | 제공자별 Admin 키 |
| 3 (보류) | 키를 넣기 싫은 API 사용자 | 이 기기의 CLI 로그로 추정한 비용 | 없음 |

3단계는 이 문서에서 대안으로만 다룬다(맨 아래).

## 데이터 출처

### 1단계 — 구독 응답에 이미 있는 금액

**Claude** (`GET /api/oauth/usage`, 지금 호출하는 엔드포인트). 2026-11-03 Pro 계정으로 확인했다:

```json
"extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null,
                 "utilization": null, "currency": null, "decimal_places": null, ... },
"spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 },
           "limit": null, "percent": 0, "severity": "normal", "enabled": false, ... }
```

- 이 계정은 추가 사용량이 꺼져 있어 값이 비어 있다. 켜진 계정의 응답은 아직 보지 못했다.
- `spend.used`는 단위가 명시돼 있다(`amount_minor` / 10^`exponent`). 그래서 `spend`를 우선 쓰고,
  `extra_usage`(`used_credits`, `decimal_places`, `monthly_limit`)는 보조로 쓴다.
- 문서화되지 않은 필드다. 형태가 다르면 조용히 표시하지 않는다(파싱 실패가 사용량 조회 실패로
  번지면 안 된다).

**Codex** (`GET https://chatgpt.com/backend-api/wham/usage`, 지금 호출하는 엔드포인트):

```json
"credits": { "has_credits": bool, "unlimited": bool, "overage_limit_reached": bool,
             "balance": "string", "approx_local_messages": [..], "approx_cloud_messages": [..] },
"spend_control": { "reached": bool, "individual_limit": null }
```

- `balance`는 문자열이다. 숫자로 읽히면 표시하고, 아니면 표시하지 않는다.
- `has_credits`가 false이고 `unlimited`도 false면 크레딧 줄을 아예 숨긴다.

### 2단계 — 조직 청구 비용 (Admin API)

**Claude (Anthropic Console 조직)**

- 엔드포인트: `GET https://api.anthropic.com/v1/organizations/cost_report` (기존 Usage and Cost API).
  - 헤더: `x-api-key: <Admin 키>`, `anthropic-version: 2023-06-01`.
  - 파라미터: `starting_at`, `ending_at`(RFC 3339), `bucket_width=1d`(비용은 하루 단위만), `limit` 최대 31,
    `group_by[]=description`(모델별 내역).
  - 응답: `data[]`는 오래된 날부터의 일 버킷(빈 날 포함), 각 버킷의 `results[]`에 `amount`·`currency`.
  - **금액 단위: USD, 센트 단위의 소수 문자열** (`"123.45"`는 $1.2345).
  - 반영 지연: 보통 5분 이내. 조회는 지속적으로 1분에 한 번까지 권장.
- 키: `sk-ant-admin01-...`. **개인 계정은 발급받을 수 없다** — Console에서 조직을 먼저 만들어야 한다.
- 신규 Usage and Cost Analytics API(`/v1/organizations/analytics/cost`, 베타 헤더
  `analytics-usage-cost-2026-08-24`)는 1분·1시간 버킷을 주지만 반영에 4~24시간이 걸린다. 메뉴바에서
  "지금까지"를 보여주는 용도로는 5분 지연인 기존 API가 맞다. 기존 API는 "legacy, remains supported"
  상태이므로, 폐기 공지가 나오면 Analytics API로 옮긴다(파서만 바뀌도록 클라이언트를 분리한다).
  - Analytics 금액은 `"41280.000000"`(센트, 소수 6자리) 형태다. 단위는 같다.

**Codex (OpenAI 조직)**

- 엔드포인트: `GET https://api.openai.com/v1/organization/costs`.
  - 헤더: `Authorization: Bearer <Admin 키>`.
  - 파라미터: `start_time`(Unix 초, 포함), `end_time`(제외), `bucket_width=1d`(현재 `1d`만 지원),
    `group_by[]=line_item`, `limit` 1~180(기본 7).
  - 응답: `data[]`의 버킷마다 `start_time`·`end_time`과 결과 배열. 결과 항목은
    `amount.value`(숫자, **달러 단위**)·`amount.currency`(`"usd"`)·`line_item`.
  - 공식 OpenAPI 명세는 결과 배열 이름을 `result`로 적고 있는데, 실제 응답 예시는 `results`를 쓴다.
    **둘 다 읽는다.**
- 키: `sk-admin-...`. 조직 Owner만 만들 수 있다. 프로젝트 키(`sk-proj-...`)로는 비용을 볼 수 없다.
- Codex CLI가 API 키로 로그인돼 있으면 `~/.codex/auth.json`이 `auth_mode: "apikey"`와 `OPENAI_API_KEY`를
  갖는다. 이 키로는 비용을 읽을 수 없지만, "구독 한도가 없는 이유"를 안내하는 데 쓴다.

### 날짜 경계: UTC

두 Admin API 모두 비용을 **UTC 하루 단위**로만 준다. 그래서 "오늘"은 UTC 날짜이고, 한국에서는 매일
09:00에 바뀐다. "이번 달"도 UTC 달 기준이다. 로컬 날짜로 맞출 방법이 없으므로 화면에 `(UTC)`를 붙여
숨기지 않는다. 청구서도 UTC 기준이라 "이번 달"은 청구서와 맞는다.

## Core 모델 (양쪽 1:1)

```swift
public struct CostAmount: Equatable, Sendable {      // 금액은 Decimal, 통화 코드는 대문자
    public let value: Decimal
    public let currency: String                       // "USD"
}

public enum CostSource: String, Sendable {
    case subscriptionExtra   // 1단계: 구독 응답의 추가 사용량·크레딧
    case adminAPI            // 2단계: 조직 청구 비용
}

public struct ProviderCost: Equatable, Sendable {
    public let provider: Provider
    public let source: CostSource
    public let monthToDate: CostAmount?   // UTC 달 1일부터
    public let today: CostAmount?         // UTC 오늘 버킷
    public let limit: CostAmount?         // 추가 사용량 한도 또는 사용자가 정한 월 예산
    public let creditBalance: CostAmount? // Codex 크레딧 잔액
    public let topItems: [CostLineItem]   // 이번 달 상위 3개 (모델/라인 아이템)
    public let measuredAt: Date
    public let dataRefreshedAt: Date?
}
```

순수 함수 (`now` 주입, 진리표 테스트 대상):

- `CostPeriod.monthStart(now:)`, `CostPeriod.dayStart(now:)` — UTC 경계.
- `AnthropicCostParser.parse(json:now:)` — 센트 문자열 → Decimal 달러, 버킷 합산, 이번 달·오늘 분리,
  설명별 합산 후 상위 3개.
- `OpenAICostParser.parse(json:now:)` — `result`/`results` 둘 다, 달러 숫자, 같은 집계.
- `SubscriptionCostParser.claude(json:)`, `.codex(json:)` — 1단계 필드. 형태가 다르면 `nil`.
- `CostFormatter.text(_:localizer:)` — `$12.34`, 1000 이상은 `$1.2K`, 0.01 미만은 `<$0.01`.
- `CostBudget.alerts(cost:budget:now:)` — 월 예산 80%·100% 알림 후보. id는
  `{provider}-cost-{80|100}-{yyyy-MM}` (UTC 달 단위로 한 번).

금액은 부동소수점을 쓰지 않는다(Swift `Decimal`, C# `decimal`). 센트 문자열을 Double로 바꾸면 합산에서
1센트 단위 오차가 난다.

## 수집

- 비용 조회는 사용량 폴링과 **별도 주기**로 돈다. `CostPolicy.nextFetch(after:succeeded:)` = 성공 후 10분,
  실패 후 5분. 1단계 값은 사용량 응답에 같이 오므로 사용량 주기를 그대로 따른다.
- 한 번 조회할 때 이번 달 1일(UTC)부터 지금까지를 `limit=31`로 받는다. 한 페이지면 충분하지만
  `has_more`/`next_page`는 처리한다.
- 429는 기존 `RateLimitBackoff`(키 지문 기반)를 재사용한다. 401·403은 "Admin 키가 거부됨"으로 분류한다.
- 실패하면 마지막 성공 값을 캐시로 보여주되, 사용량과 같은 규칙으로 표시를 구분한다(`캐시 데이터 사용
  중`). 금액은 이미 쓴 돈이라 시간이 지나도 틀리지 않으므로, 캐시 유지 기간은 사용량보다 길게(같은 UTC
  달 안) 둔다.
- 히스토리: 하루 마감 금액만 남긴다(일 단위 막대 차트용, 4단계 후보). 이번 범위에서는 저장하지 않는다.

## 자격 증명 저장 (2단계)

Admin 키는 조직 관리 권한(키 생성·삭제, 멤버 관리)까지 가진 강한 키다.

- macOS: 앱 소유 키체인 항목(`service: "Token Tracker"`, `account: "anthropic-admin"` /
  `"openai-admin"`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). 파일에 쓰지 않는다.
- Windows: DPAPI(`ProtectedData`, CurrentUser)로 암호화해 `%APPDATA%\Token Tracker\admin-keys.dat`.
  `System.Security.Cryptography.ProtectedData` 패키지가 필요하다.
- 진단 정보·로그·알림에는 키를 넣지 않는다. 설정 화면과 진단에는 `…ab12`(끝 4자리)와 마지막 조회 결과만.
- 설정 화면에 안내를 둔다: 이 앱 전용 키를 따로 만들고, Anthropic은 만료일을 걸 것(문서 권장).
  읽기 전용 권한을 고를 수 있는 제공자라면 그것을 쓰라고 안내한다(구현 시 각 Console에서 확인).
- 약관: 사용자가 자기 API 키를 관리하는 것은 Claude Code 약관이 허용하는 범위다. 구독 로그인
  정보(Claude.ai 세션·OAuth)를 앱이 보관하는 것과는 다르다.

## 설정

| 키 (macOS `Settings` / Windows `AppSettings`) | 기본값 | 설명 |
|---|---|---|
| `showSubscriptionExtras` / `ShowSubscriptionExtras` | true | 1단계 금액 줄 표시 |
| `claudeCostEnabled` / `ClaudeCostEnabled` | false | Claude Admin API 비용 조회 (키가 있어야 의미) |
| `codexCostEnabled` / `CodexCostEnabled` | false | OpenAI Admin API 비용 조회 |
| `claudeMonthlyBudget` / `ClaudeMonthlyBudget` | 0 | 월 예산(USD, 0이면 끔) |
| `codexMonthlyBudget` / `CodexMonthlyBudget` | 0 | 월 예산(USD, 0이면 끔) |

기존 `claudeEnabled`·`codexEnabled`는 "구독 한도 표시"로 의미를 좁힌다. API만 쓰는 사용자는 구독 한도를
끄고 비용만 켤 수 있어야 `로그인 필요` 카드가 사라진다. 키 이름은 바꾸지 않으므로 마이그레이션은 없다.

설정 화면 배치(양쪽): 제공자 섹션의 각 제공자 아래에 "구독 한도" 토글, "API 비용" 토글 + `Admin 키…`
버튼(시트에서 붙여넣기·삭제·마지막 4자리 표시), "월 예산" 숫자 입력.

## 화면

### macOS 팝업

제공자 카드 안에서 기존 5h·7d 막대 아래에 금액 영역을 둔다. 구독 한도가 꺼져 있으면 금액 영역만 있는
카드가 된다.

```
Claude  [api]                                   ● 정상
  이번 달 (UTC)                              $42.18
  ▓▓▓▓▓▓▓▓░░░░░░░░  예산 $100 중 42%
  오늘 (UTC) $3.07 · Opus 71% · Sonnet 27%
Codex   [plus]                                  ● 정상
  5시간 ... 7일 ...                             (기존)
  크레딧 잔액  $18.40
```

- 금액 숫자는 오른쪽 정렬, 기존 퍼센트와 같은 굵기.
- 예산이 없으면 막대를 그리지 않는다. 80% 이상이면 주황, 100% 이상이면 빨강(기존 `UsageLevel` 규칙과 같은
  색 체계).
- 1단계 Claude 추가 사용량: `추가 사용량  $1.86 / $5.00` + 막대(한도 대비).
- 상태 배지: Admin API 값은 `정상`, 캐시는 `캐시 데이터 사용 중`, 키 거부는 `Admin 키 거부됨`(빨강).
- 데이터 반영 시각: `data_refreshed_at`이 있으면(Analytics API로 옮긴 뒤) 도움말에 `기준 시각 10:42`.

### 메뉴바

- 구독 한도가 켜져 있으면 지금과 같다(퍼센트). 금액은 메뉴바에 나오지 않는다.
- 구독 한도가 꺼지고 비용만 켜진 제공자는 이번 달 금액을 쓴다: `Cl $42`, 로고 모드면 로고 + `$42`.
  둘 다 비용만이면 `Cl $42 · Cdx $8`.
- 예산 80% 이상이면 기존 7일 경고처럼 강조색을 쓴다.

### Windows

- 트레이 메뉴 제공자 하위 메뉴에 `이번 달 (UTC): $42.18`, `오늘 (UTC): $3.07`, `예산: $100 중 42%`,
  상위 항목 줄을 추가한다.
- 툴팁 첫 줄: 구독 한도가 없는 제공자는 `Claude $42 (이번 달)`.
- 트레이 아이콘(16×16)은 퍼센트를 그리는 자리라 금액을 그리지 않는다. 구독 한도가 모두 꺼져 있으면
  아이콘에 `$`를 그린다.

### 알림

- 월 예산 80%, 100% 도달 시 제공자별로 한 번씩(같은 UTC 달 안에서는 다시 보내지 않는다).
- 1단계: Claude `spend.severity`가 `normal`이 아니게 바뀌면 한 번, Codex `overage_limit_reached`가 true가 되면
  한 번.
- 기존 알림처럼 `알림 받기`가 꺼져 있으면 보내지 않는다.

## 현지화

새 키(사전 4개 + enum 2개): `costThisMonth` "이번 달 (UTC)" / "This month (UTC)", `costToday`,
`costBudget` "예산 {limit} 중 {percent}%", `costExtraUsage` "추가 사용량", `costCreditBalance`
"크레딧 잔액", `costAdminKeyRejected` "Admin 키 거부됨", `costBudgetAlertTitle`, `costBudgetAlertBody`
"{provider} 이번 달 비용 {amount} — 예산의 {percent}%", 설정 문구들. 금액 형식(`$`, 천 단위 `K`)은
언어와 무관하게 같다.

## 테스트

양쪽 Core에 같은 진리표:

- 파서: 문서 예시를 본뜬 고정 JSON — Anthropic 센트 문자열(`"123.45"` → $1.2345), 빈 날 버킷 포함,
  여러 페이지, OpenAI `result`/`results` 둘 다, 통화 대소문자.
- UTC 경계: 한국 시간 08:59와 09:01에 "오늘" 버킷이 바뀌는지, 달 마지막 날 → 다음 달 1일.
- 합산: Decimal로 31일 × 여러 항목을 더해 센트 오차가 없는지.
- 예산 알림: 79/80/100%, 예산 0, 같은 달 중복 억제, 달이 바뀌면 재무장.
- 1단계: 추가 사용량 꺼짐(지금 실측 응답 그대로) → 표시 없음, 켜짐(가정한 형태) → 표시, 이상한 형태 → 표시 없음.
- 클라이언트: 가짜 HTTP 핸들러로 401·403·429·200 (Windows는 `QueueHttpMessageHandler`, macOS는
  `HTTPClient` 주입).

실제 검증에는 Admin 키가 필요하다. 개발자 계정에 Anthropic 조직과 OpenAI 조직의 Admin 키를 각각 만들어
테스트하고, 키는 키체인/DPAPI에만 넣는다. 1단계 Claude 추가 사용량은 켜진 계정을 볼 수 없으면 파서
테스트까지만 하고, 화면에는 실제 값을 본 뒤에 노출한다.

## 구현 순서 (PR 단위)

1. Core: `CostAmount`·파서·포매터·UTC 경계·예산 알림 + 양쪽 진리표 (UI 없음).
2. 1단계: Codex 크레딧 잔액 표시(실제 값 확인 가능), Claude 추가 사용량은 플래그 뒤에.
3. 2단계 수집: Admin 키 저장(macOS 키체인, Windows DPAPI), 클라이언트 두 개, 주기·캐시·백오프, 진단 줄.
4. 2단계 화면: 설정(토글·키 시트·예산), 팝업 카드, 메뉴바 규칙, Windows 메뉴·툴팁.
5. 예산 알림, 문서(README·WORK_SUMMARY), 릴리스.

## 대안: 로컬 로그 추정 (3단계, 보류)

Claude Code의 `~/.claude/projects/**/*.jsonl`과 Codex의 세션 로그에서 토큰 수를 읽어 가격표로 곱하는
방식(ccusage와 같음). 키가 필요 없지만 이 기기에서 CLI로 쓴 것만 잡히고, 가격표를 양쪽 Core에서 계속
맞춰야 하며, 청구서와 다르다. 상태줄의 `cost.total_cost_usd`도 세션 단위 추정치라(`/clear`하면 0) 월 합계로는
쓸 수 없다. 2단계를 쓸 수 없는 사용자(조직을 만들 수 없거나 Admin 키를 넣기 싫은 경우)를 위해, 2단계 이후에
필요하면 `추정` 배지를 달아 추가한다.

## 결정이 필요한 것

1. "오늘"을 UTC 날짜로 보여주는 것이 괜찮은가 (로컬 날짜로는 API가 주지 않는다).
2. 예산 알림 기준 80%·100%가 적당한가.
3. 구독 한도와 비용이 둘 다 켜진 경우 메뉴바에 금액을 같이 보여줄 것인가 (초안: 보여주지 않음).
4. Admin 키를 메뉴바 앱에 보관하는 위험을 감수할 것인가 (초안: 키체인·DPAPI + 전용 키 안내).
5. 3단계(로컬 추정)를 언젠가 할 것인가.

## 참고

- [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)
- [Usage and Cost Analytics API](https://platform.claude.com/docs/en/manage-claude/usage-cost-analytics-api)
- [OpenAI Costs API](https://platform.openai.com/docs/api-reference/usage/costs) ·
  [OpenAPI 명세](https://github.com/openai/openai-openapi)
- [Claude Code 상태줄 — cost 필드](https://code.claude.com/docs/en/statusline)
- [Claude Code — Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
