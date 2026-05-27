# Token Tracker Agent Notes

## 목적

Token Tracker는 Claude와 Codex의 사용량 잔량을 작은 메뉴바/트레이 앱으로 보여주는 프로젝트다.
macOS는 Swift/AppKit 메뉴바 앱이고, Windows는 .NET WinForms 트레이 앱이다.

## 핵심 동작

- Claude와 Codex의 5시간/7일 사용량 잔량을 퍼센트로 표시한다.
- 기본 표시는 5시간 잔량이며, 7일 잔량이 10% 이하이면 7일 잔량을 우선 표시한다.
- 연결 실패 또는 비활성화된 provider는 `--` 또는 unavailable 상태로 표시한다.
- 표시 모드는 `Lowest remaining`, `Claude + Codex`, `Codex only`, `Claude only`를 지원한다.
- provider 표기는 축약 텍스트(`Cdx / Cl`) 또는 공식 아이콘 기반 표기를 지원한다.
- Claude/Codex provider별 활성화, 새로고침 주기, 언어, 로그인 시 실행 설정을 제공한다.

## 저장소 구조

```text
.
├── Package.swift
├── Sources/
│   ├── TokenTrackerCore/
│   ├── TokenTrackerMenuBar/
│   └── TokenTrackerSmokeTests/
├── windows/
│   ├── TokenTracker.Windows/
│   ├── TokenTracker.Windows.Core/
│   └── TokenTracker.Windows.Tests/
├── scripts/
│   └── build_app.sh
├── dist/
├── README.md
├── WORK_SUMMARY.md
└── agent.md
```

## macOS 앱

- 진입점: `Sources/TokenTrackerMenuBar/main.swift`
- 메뉴바 UI: `Sources/TokenTrackerMenuBar/AppDelegate.swift`
- 로그인 항목 관리: `Sources/TokenTrackerMenuBar/LoginItemManager.swift`
- 공통 로직: `Sources/TokenTrackerCore/`
- 스모크 테스트: `Sources/TokenTrackerSmokeTests/main.swift`

macOS 앱은 `NSStatusItem`을 사용한다.
상태바 텍스트/아이콘은 `AppDelegate`에서 이미지로 렌더링한다.
상세 메뉴는 `NSMenu`와 커스텀 `InfoMenuItemView`로 구성한다.
설정은 `UserDefaults` 기반 `Settings`에 저장한다.

## Windows 앱

- 진입점: `windows/TokenTracker.Windows/Program.cs`
- 트레이 UI: `windows/TokenTracker.Windows/TrayAppContext.cs`
- 트레이 아이콘 렌더링: `windows/TokenTracker.Windows/TrayIconRenderer.cs`
- 시작 프로그램 설정: `windows/TokenTracker.Windows/StartupManager.cs`
- provider 로고 관리: `windows/TokenTracker.Windows/ProviderLogoStore.cs`
- 코어 로직: `windows/TokenTracker.Windows.Core/`
- 테스트: `windows/TokenTracker.Windows.Tests/Program.cs`

Windows 앱은 `.NET 10`과 WinForms `NotifyIcon`을 사용한다.
`TrayAppContext`가 메뉴 구성, 새로고침 타이머, provider 토글, 설정 저장을 담당한다.
Windows 알림 영역 아이콘 상시 표시는 앱이 강제할 수 없으므로 `ms-settings:taskbar`를 열어 사용자가 직접 켜야 한다.

## 사용량 조회

Codex:

- 인증 파일: `~/.codex/auth.json`
- 필요한 값: `tokens.access_token`, `tokens.account_id`
- API: `https://chatgpt.com/backend-api/wham/usage`
- `used_percent`를 `100 - used_percent`로 변환해 잔량으로 표시한다.

Claude:

- macOS는 Keychain을 우선 사용하고 실패 시 `~/.claude/.credentials.json`을 사용한다.
- Windows는 `~/.claude/.credentials.json`의 `claudeAiOauth.accessToken`을 읽는다.
- API: `https://api.anthropic.com/api/oauth/usage`
- `utilization`을 `100 - utilization`으로 변환해 잔량으로 표시한다.

## 표시 규칙

- `DisplayFormatter`가 퍼센트, tooltip, 상세 라인, reset 시간 표시를 담당한다.
- 7일 잔량이 10% 이하이면 7일 잔량 표시가 5시간 잔량보다 우선한다.
- 7일 잔량 기준으로 표시되는 값은 경고색으로 렌더링한다.
- API 실패 시 오래된 Codex 로컬 로그 값을 최신 잔량처럼 표시하지 않는다.
- macOS `UsageService`는 최근 성공 캐시를 최대 1시간 stale cache로 사용할 수 있다.

## 빌드와 실행

macOS 스모크 테스트:

```bash
swift run TokenTrackerSmokeTests
```

macOS 릴리즈 빌드:

```bash
swift build -c release
scripts/build_app.sh
```

macOS 앱 실행:

```bash
open ".build/Token Tracker.app"
```

Windows 스모크 테스트:

```powershell
dotnet run --project windows/TokenTracker.Windows.Tests
```

Windows 앱 실행:

```powershell
dotnet run --project windows/TokenTracker.Windows
```

Windows 릴리즈 빌드:

```powershell
dotnet publish windows/TokenTracker.Windows `
  -c Release `
  -r win-x64 `
  --self-contained true `
  /p:PublishSingleFile=true
```

## 검증 주의

- Windows UI와 WinForms 컴파일 검증은 Windows + .NET 10 환경에서 수행하는 것이 가장 안전하다.
- macOS에서 Windows 프로젝트를 만질 때는 `dotnet`이 없을 수 있으므로 최소한 `git diff --check`로 whitespace를 확인한다.
- UI 메뉴 폭/높이 문제는 긴 오류 문자열과 provider 상세 행이 원인이 될 수 있다.
- Windows 트레이 메뉴는 루트 메뉴를 작게 유지하고, provider 상세 정보는 서브메뉴로 접는 방향을 선호한다.

## 배포 메모

- macOS 배포물은 `dist/TokenTracker-vX.Y.Z-macOS.dmg` 형태로 관리된다.
- 호환성 있는 DMG는 HFS+ 형식으로 만드는 것이 안전하다.
- 일반 사용자용 macOS 배포에는 Developer ID 서명과 Apple notarization이 필요하다.
- Windows 배포물은 self-contained single-file publish 결과물을 zip으로 묶는 방식이다.

## 작업 시 주의점

- macOS와 Windows 구현은 별도 UI 코드지만 표시 규칙은 최대한 동일하게 유지한다.
- 공통 계산/포맷 변경은 Swift `TokenTrackerCore`와 C# `TokenTracker.Windows.Core` 양쪽을 같이 확인한다.
- 기존 사용자 설정 키와 저장 경로를 바꿀 때는 마이그레이션 영향을 먼저 확인한다.
- 리프레시 실패가 앱 종료나 메뉴 깨짐으로 이어지지 않도록 unavailable 상태를 유지한다.
- 긴 오류 메시지는 메뉴 크기를 키우지 않도록 truncate 또는 별도 tooltip/submenu로 처리한다.
