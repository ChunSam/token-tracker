# Token Tracker 작업 요약

## 목적

Claude Code와 Codex의 토큰 한도 잔량을 퍼센트로 상시 확인하는 macOS 메뉴바 앱과 Windows 트레이 앱.
두 플랫폼은 Core 로직을 1:1로 맞춘다 — 같은 규칙, 같은 테스트.

## 구현 범위

- Swift Package 기반 macOS 네이티브 메뉴바 앱 (`NSStatusItem`)
- .NET WinForms `NotifyIcon` 기반 Windows 트레이 앱
- Claude Code / Codex 사용량 조회 (API 우선, 실패 시 마지막 성공 값을 한도 시간 안에서 유지, 그 뒤 `--`)
- 메뉴바 표시 모드 4종, 제공자 표기 2종(약어 / 공식 아이콘), 리셋까지 남은 시간 표기
- 설정 창: 표시 · 제공자 on/off · 새로고침 간격 · 언어(한/영) · 알림 · 히스토리 · 예측
- 알림: 5시간/7일 잔량 부족, 리셋 임박, 리셋 전 소진 예측 (macOS `UserNotifications` / Windows 풍선)
- 로컬 히스토리(기본 7일) 저장, 24시간 추세, 유니코드 스파크라인, CSV 내보내기
- 소진 예측(현재 소모 속도로 0%에 닿는 시각), 업데이트 일시중지(1h / 3h / 재개할 때까지)
- 만료 토큰 사전 감지, 429 지수 백오프, 제공자별 쿨다운 파일, 중복 실행 방지
- 진단 정보 복사 — 앱 버전·설정·히스토리·자격 증명 저장소(키체인/파일)와 그 신선도
- 부팅 시 자동 시작, 전용 앱 아이콘, 라이트/다크 대응
- CI: 양 플랫폼 스모크 테스트 + 배포할 `.app`/exe를 실제로 조립해 검사하는 release-path smoke, 버전 기본값 드리프트 검사
- 릴리스 워크플로: 태그 → macOS universal DMG + Windows x64/arm64 zip + 검증되는 sha256 → GitHub Release

## 프로젝트 구조

```text
Token tracker/
├── Package.swift
├── Sources/
│   ├── TokenTrackerCore/        순수 로직 (조회·포맷·예측·알림·설정·현지화)
│   ├── TokenTrackerMenuBar/     AppKit UI (상태 아이템·메뉴·설정 창·알림·진단)
│   └── TokenTrackerSmokeTests/  Core 스모크 테스트 (실행 타깃)
├── windows/
│   ├── TokenTracker.Windows/        WinForms 트레이 앱
│   ├── TokenTracker.Windows.Core/   Core의 C# 포트
│   └── TokenTracker.Windows.Tests/  Core 스모크 테스트
├── scripts/
│   ├── build_app.sh             release 빌드 → `.app` 번들 (universal 지원)
│   └── verify_app_bundle.swift  조립된 `.app`이 자기 리소스를 찾는지 검사
├── .github/workflows/
│   ├── ci.yml                   PR/main: 빌드·테스트·release-path smoke·버전 드리프트
│   ├── release.yml              태그 push: DMG·zip·체크섬·GitHub Release
│   └── windows-release.yml      Windows만 수동 빌드
├── plans/                       기능 계획서와 세션 handoff 기록
├── .claude/proposals/           /wrap 회고 제안서
├── README.md                    사용자 문서 (설치·표시 규칙·문제 해결·빌드)
├── SECURITY_AUDIT.md
└── WORK_SUMMARY.md
```

## 핵심 기능

### 메뉴바 표시

표시 모드는 설정 창에서 고른다.

- `Lowest remaining`: Claude/Codex 중 잔량이 더 낮은 값을 `AI 72%` 형태로 표시
- `Claude + Codex`: `Cdx 91% · Cl 63%` 형태로 둘 다 표시
- `Codex only`: `Cdx 91%`
- `Claude only`: `Cl 63%`

제공자 표기는 약어(`Cdx` / `Cl`) 또는 공식 아이콘 중 선택한다.

표시 규칙:

- 기본은 5시간 잔량. 7일 잔량이 10% 이하면 7일 잔량을 대신 보여주고 파스텔 레드로 강조한다.
- 표시 중인 창의 리셋까지 남은 시간을 퍼센트 옆에 붙인다 (`Cl 63% 2h10m`). 30초마다 로컬에서
  다시 그리므로 새로고침 간격과 무관하게 분 단위로 맞는다. 설정에서 끌 수 있다.
- 캐시된 값(`staleCache`)에는 남은 시간을 붙이지 않는다 — 값은 멈춰 있는데 시간만 흘러 틀린
  시간을 보여주게 되기 때문이다.

### 상세 메뉴

제공자별 블록:

- 5시간 / 7일 잔량, 상태(정상 · 캐시 데이터 · 요청 제한 · 다시 로그인 필요 · …)와 설명, 복구 방법
- Claude 토큰이 만료됐고 자격 증명 저장소가 8시간 넘게 갱신되지 않았으면 경과 시간 한 줄 추가
  (`자격 증명이 2d 3h째 갱신되지 않음`) — "다시 로그인했는데도 안 되는" 이유가 이 줄이다
- 예상 소진(`~2h 10m`, 리셋 전 소진이면 표시), 5시간/7일 리셋, 데이터 출처, 플랜, 기술 오류

그 아래:

- 업데이트 시각, 마지막 성공 업데이트
- 지금 새로고침, 설정…, 업데이트 일시중지(1시간 / 3시간 / 재개할 때까지)
- 진단 ▸ 진단 정보 복사, Claude/Codex 인증 파일 열기, 실행 중인 인스턴스 수
- 히스토리 ▸ 24시간 추세(5h·7d 변화량), 제공자별 스파크라인, 보관 기간, CSV 내보내기
- 로그인 시 실행, 종료

### Codex 사용량 조회

1. `~/.codex/auth.json`에서 access token과 account id를 읽는다.
2. JWT `exp`로 만료를 먼저 확인한다 — 만료된 토큰으로 요청하면 401만 돌아와 원인을 알 수 없다.
3. 쿨다운 파일(`codex-rate-limit.json`)에 유효한 쿨다운이 있으면 요청하지 않는다.
4. `https://chatgpt.com/backend-api/wham/usage`를 호출한다.
5. 응답의 rate-limit 창을 **위치가 아니라 길이**로 5h/7d 레인에 배정한다 — 2026-07부터 API가
   주간 창을 `primary_window`로 보낼 수 있어서 위치 매핑은 주간 사용량을 5h 자리에 보여준다.
6. `used_percent` → `remainingPercent = 100 - used_percent`.
7. 실패하면 마지막 성공 값을 `staleCache`로 유지한다(아래 공통 정책). 로컬 로그 fallback은 없다.

### Claude 사용량 조회

1. macOS Keychain의 `Claude Code-credentials`, 그다음 `~/.claude/.credentials.json`을 후보로 읽는다.
2. `expiresAt`이 지난 후보는 제외한다. 전부 만료면 요청 없이 "다시 로그인 필요"로 보고한다 —
   만료 토큰으로 요청하면 429가 돌아와 백오프가 그것을 진짜 한도로 오해한다.
3. 쿨다운 파일(`claude-rate-limit.json`)에 유효한 쿨다운이 있으면 요청하지 않는다. 쿨다운은 그것을
   만든 토큰의 지문에 묶여 있어 다시 로그인하면 즉시 풀린다.
4. `https://api.anthropic.com/api/oauth/usage`를 호출한다. `utilization` → `remainingPercent = 100 - utilization`.
5. 429면 쿨다운을 기록한다: `max(120초, Retry-After)`에서 시작해 연속 실패마다 2배(상한 1800초),
   지터 가산. 서버가 더 긴 `Retry-After`를 주면 그쪽을 따른다.

공통 정책 — 새 값을 못 얻은 제공자는 마지막 성공 값을 `staleCache`로 계속 보여준다. 유지 기간은
설정의 `마지막 값 유지 기간`(기본 12시간). 캐시 값은 히스토리·추세·예측에 들어가지 않고 남은 시간도
붙지 않는다.

토큰 갱신은 각 CLI(`claude`, `codex`)만 한다. Token Tracker는 읽기만 한다. 특히 Claude는 데스크톱
앱이 이 저장소를 갱신하지 않으므로 터미널에서 `claude`를 가끔 실행해야 한다 — README
"사용량을 못 불러올 때" 참고.

### 알림

`알림` 설정을 켜면 5시간 잔량 부족(기본 20%), 7일 잔량 부족(기본 10%), 리셋 임박(기본 10분 전),
그리고 켜둔 경우 "리셋 전 소진 예상"을 보낸다. 같은 창 인스턴스에 대해 한 번만 보내도록 id로 중복
제거한다.

### 히스토리 · 예측 · 일시중지

- 히스토리는 실측값(`api`)만 저장한다. 60초 안의 연속 기록은 합치고 보관 기간(기본 7일)을 넘긴 것은
  버린다.
- 예측은 현재 창 인스턴스의 기록(직전 리셋 이후)만으로 소모 속도를 구한다. 10분 미만 구간이거나
  줄어들지 않으면 예측하지 않는다. 5h 창이 비면(현재 Codex) 7d 창으로 대신한다.
- 일시중지는 `pollPausedUntil`로 저장돼 재시작해도 유지된다. `지금 새로고침`은 명시적 요청이므로
  일시중지를 푼다.

### 부팅 시 자동 시작

`ServiceManagement`의 `SMAppService.mainApp`을 사용해 로그인 항목을 등록/해제한다.

메뉴 항목:

- `Launch at Login: Enabled`
- `Launch at Login: Disabled`
- `Launch at Login: Requires approval in System Settings`
- `Launch at Login: App bundle not found`

## 주요 파일

macOS UI (`Sources/TokenTrackerMenuBar/`)

- `AppDelegate.swift` — 새로고침 루프, 타이머, 메뉴 구성 호출, 액션 핸들러
- `StatusItemRenderer.swift` — 메뉴바 텍스트/아이콘 그리기. 리소스 번들은 `Bundle.module`이 아니라
  `Contents/Resources`에서 직접 찾는다(릴리스 `.app`에서 `Bundle.module`은 trap한다)
- `StatusMenuBuilder.swift` — 상세 메뉴 조립
- `PreferencesWindowController.swift` — 설정 창
- `UsageNotificationCoordinator.swift` — 알림 권한·중복 제거·발송
- `DiagnosticsReporter.swift` — 진단 텍스트
- `LoginItemManager.swift` — 로그인 항목 등록/해제

Core (`Sources/TokenTrackerCore/`)

- `ClaudeUsageClient.swift` / `CodexUsageClient.swift` — 조회, 만료 감지, 쿨다운
- `CodexWindowMapper.swift` — 창 길이 기준 5h/7d 배정
- `UsageService.swift` — 두 제공자 통합, stale cache 정책
- `CredentialExpiry.swift` / `CredentialSource.swift` — 만료 판정, 저장소 종류·신선도, 메뉴 안내 줄
- `RateLimitBackoff.swift` / `RateLimitState.swift` / `RateLimitStore.swift` — 429 백오프와 영속화
- `UsageIssueFormatter.swift` — 오류 문자열 → 상태/설명/복구 안내
- `DisplayFormatter.swift` — 메뉴바 문자열, 표시 창 선택, 리셋 카운트다운
- `UsageForecast.swift` / `Sparkline.swift` / `UsageHistoryStore.swift` — 예측, 스파크라인, 히스토리
- `UsageAlertEvaluator.swift` — 알림 후보 계산
- `PauseController.swift` / `InstanceArbiter.swift` — 일시중지, 중복 실행 판정
- `Settings.swift` / `Localization.swift` / `Paths.swift` — UserDefaults, 한/영 문자열, 파일 경로

Windows (`windows/`)

- `TokenTracker.Windows/TrayAppContext.cs` — 트레이 메뉴와 새로고침 루프 (macOS `AppDelegate` +
  `StatusMenuBuilder`에 대응)
- `TokenTracker.Windows.Core/` — 위 Core 파일들의 C# 포트. 파일명이 1:1로 대응한다
- `TokenTracker.Windows.Tests/Program.cs` — Core 스모크 테스트

빌드·배포

- `scripts/build_app.sh` — release 빌드 후 `.app` 조립, `AppIcon.png` → `AppIcon.icns`.
  `APP_VERSION`/`APP_BUILD` 로컬 기본값을 가진다(릴리스는 태그·run number로 덮어씀)
- `scripts/verify_app_bundle.swift` — 조립된 `.app`의 실행 파일·Info.plist·리소스 번들 검사
- `windows/TokenTracker.Windows/TokenTracker.Windows.csproj` — `<Version>` 로컬 기본값.
  `build_app.sh`의 `APP_VERSION`과 같아야 하며 CI가 드리프트를 막는다

## 빌드 및 실행

macOS 스모크 테스트:

```bash
swift run TokenTrackerSmokeTests
```

앱 번들 생성과 검사:

```bash
scripts/build_app.sh
swift scripts/verify_app_bundle.swift ".build/Token Tracker.app"
```

Intel/Apple Silicon 겸용은 `APP_ARCHS="arm64 x86_64" scripts/build_app.sh`.

앱 실행:

```bash
open ".build/Token Tracker.app"
```

Windows 쪽 명령(`dotnet run`, `dotnet publish`)은 README "개발" 절에 있다. **이 개발 머신에는 dotnet이
없으므로 Windows 코드의 컴파일 검증은 CI가 유일한 게이트다.**

## 검증 기준

PR마다 CI가 다음을 확인한다.

- macOS: 버전 기본값 일치 → `swift build` → 스모크 테스트 → `build_app.sh` → `verify_app_bundle.swift`
- Windows: Core 테스트 → WinForms 빌드 → self-contained single-file publish → publish된 exe의 버전 스탬프

릴리스 워크플로는 여기에 더해 DMG/zip을 만들고, 방금 쓴 sha256 파일이 그 자리에서 검증되는지
확인한 뒤 GitHub Release에 올린다.

배포 후에는 산출물을 실제로 내려받아 설치·실행해 본다. 소스가 빌드된다는 것과 배포된 파일이
동작한다는 것은 다른 주장이다 — 1.1.5까지의 DMG는 아이콘 표기에서 즉시 죽었고, Windows 앱은
모든 빌드가 `1.0.0`을 보고했으며, 체크섬 파일은 받은 자리에서 검증되지 않았다. 셋 다 소스 레벨
CI로는 보이지 않았다.

설치 확인:

```bash
open "/Applications/Token Tracker.app"
osascript -e 'tell application "System Events" to exists process "TokenTrackerMenuBar"'
```

## 현재 제약

- Claude 한도 퍼센트는 API 또는 최근 성공 캐시에 의존한다.
- Claude 로컬 JSONL 로그는 토큰 사용량은 제공하지만 한도 대비 퍼센트는 제공하지 않으므로 fallback으로
  쓰지 않는다.
- Claude 액세스 토큰(약 8시간)은 터미널 CLI만 갱신한다. 데스크톱 앱 위주로 쓰면 토큰이 만료돼
  마지막 값만 남는다.
- 첫 Claude Keychain 접근 시 macOS 권한 허용 창이 뜰 수 있다.
- 산출물은 unsigned `.app`이다. 다른 Mac에서 더블클릭으로 열려면 Developer ID 서명과 notarization이
  필요하다.
- 이 개발 머신에는 dotnet이 없다.

## 다음 개선 후보

- 로그인 항목 승인 상태를 System Settings로 바로 여는 버튼 추가
- signed/notarized 배포 빌드 구성
- Codex도 자격 증명 저장소 신선도를 메뉴에 표시 (지금은 Claude만)
