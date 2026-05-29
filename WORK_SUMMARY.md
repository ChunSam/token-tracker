# Token Tracker 작업 요약

## 목적

MacBook 상단 메뉴바에서 Claude Code와 Codex의 토큰 한도 잔량을 퍼센트로 확인하는 macOS 메뉴바 앱을 제작했다.

## 구현 범위

- Swift Package 기반 macOS 네이티브 메뉴바 앱 생성
- AppKit `NSStatusItem` 기반 상단 메뉴바 표시
- .NET WinForms `NotifyIcon` 기반 Windows 트레이 앱 추가
- Claude Code / Codex 사용량 조회
- API 우선 조회, 실패 시 unavailable 표시
- 메뉴바 표시 모드 4종 지원
- 부팅 시 자동 시작 설정 지원
- 전용 앱 아이콘 추가 및 macOS 번들 아이콘 연결
- `.app` 번들 생성 스크립트 추가
- smoke test 실행 타깃 추가

## 프로젝트 구조

```text
Token tracker/
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
├── .gitignore
└── WORK_SUMMARY.md
```

## 핵심 기능

### 메뉴바 표시

사용자는 메뉴에서 표시 모드를 선택할 수 있다.

- `Lowest remaining`: Claude/Codex 중 5시간 잔량이 더 낮은 값을 `AI 72%` 형태로 표시
- `Claude + Codex`: `Cdx 91% · Cl 63%` 형태로 둘 다 표시
- `Codex only`: `Cdx 91%` 형태로 Codex만 표시
- `Claude only`: `Cl 63%` 형태로 Claude만 표시

잔량 색상 정책:

- 50% 이상: 기본 색상
- 20~49%: 주황색
- 20% 미만: 빨간색

### 상세 메뉴

메뉴 클릭 시 다음 정보를 표시한다.

- Claude 5시간 / 7일 잔량
- Codex 5시간 / 7일 잔량
- 리셋까지 남은 시간
- 데이터 출처
- plan 정보
- 오류 메시지
- 수동 새로고침
- 표시 모드 선택
- 로그인 시 자동 실행 토글
- 앱 종료

### Codex 사용량 조회

1. 우선 `~/.codex/auth.json`에서 access token과 account id를 읽는다.
2. `https://chatgpt.com/backend-api/wham/usage`를 호출한다.
3. API 실패 시 오래된 로컬 로그 값을 사용하지 않고 unavailable로 표시한다.
4. `used_percent`를 `remainingPercent = 100 - used_percent`로 변환한다.

### Claude 사용량 조회

1. 우선 macOS Keychain의 `Claude Code-credentials`를 읽는다.
2. Keychain 실패 시 `~/.claude/.credentials.json`을 읽는다.
3. `https://api.anthropic.com/api/oauth/usage`를 호출한다.
4. `utilization`을 `remainingPercent = 100 - utilization`로 변환한다.
5. 실패 시 최근 성공 캐시가 있으면 최대 1시간 동안 stale cache로 표시한다.

### 부팅 시 자동 시작

`ServiceManagement`의 `SMAppService.mainApp`을 사용해 로그인 항목을 등록/해제한다.

메뉴 항목:

- `Launch at Login: Enabled`
- `Launch at Login: Disabled`
- `Launch at Login: Requires approval in System Settings`
- `Launch at Login: App bundle not found`

## 주요 파일

- `Sources/TokenTrackerMenuBar/AppDelegate.swift`
  - 메뉴바 UI, 메뉴 구성, 새로고침, 표시 모드 변경 처리
- `Sources/TokenTrackerMenuBar/LoginItemManager.swift`
  - 로그인 시 자동 시작 등록/해제
- `Sources/TokenTrackerCore/CodexUsageClient.swift`
  - Codex API 사용량 조회
- `Sources/TokenTrackerCore/CodexLogReader.swift`
  - Codex 로컬 로그 reader. 현재 메뉴바 표시 fallback으로는 사용하지 않는다.
- `Sources/TokenTrackerCore/ClaudeUsageClient.swift`
  - Claude API 사용량 조회
- `Sources/TokenTrackerCore/UsageService.swift`
  - Claude/Codex 조회 통합, stale cache 처리
- `Sources/TokenTrackerCore/DisplayFormatter.swift`
  - 메뉴바 문자열과 상세 표시 포맷
- `Sources/TokenTrackerMenuBar/Resources/AppIcon.png`
  - Token Tracker 앱 아이콘 원본 PNG
- `scripts/build_app.sh`
  - release 빌드 후 `.app` 번들 생성
  - `AppIcon.png`에서 표준 macOS `AppIcon.icns`를 생성하고 `CFBundleIconFile`로 연결
- `windows/TokenTracker.Windows`
  - Windows 작업표시줄 트레이 앱
- `windows/TokenTracker.Windows.Core`
  - Windows용 C# 사용량 조회, 표시 계산, 설정 저장 로직
- `windows/TokenTracker.Windows.Tests`
  - Windows 코어 로직 smoke test 실행 프로젝트

## 빌드 및 실행

Smoke test:

```bash
swift run TokenTrackerSmokeTests
```

Release build:

```bash
swift build -c release
```

앱 번들 생성:

```bash
scripts/build_app.sh
```

`scripts/build_app.sh`는 `sips`와 `iconutil`로 `Sources/TokenTrackerMenuBar/Resources/AppIcon.png`를 여러 해상도의 iconset으로 변환한 뒤 `.build/Token Tracker.app/Contents/Resources/AppIcon.icns`에 저장한다.

앱 실행:

```bash
open ".build/Token Tracker.app"
```

## 검증 결과

다음 명령을 실행해 통과를 확인했다.

```bash
swift run TokenTrackerSmokeTests
swift build -c release
scripts/build_app.sh
```

생성된 앱:

```text
.build/Token Tracker.app
```

최근 아이콘 적용 작업 검증:

```bash
scripts/build_app.sh
plutil -p ".build/Token Tracker.app/Contents/Info.plist"
file ".build/Token Tracker.app/Contents/Resources/AppIcon.icns"
```

설치 확인:

```bash
open "/Applications/Token Tracker.app"
osascript -e 'tell application "System Events" to exists process "TokenTrackerMenuBar"'
```

## 현재 제약

- Claude 한도 퍼센트는 API 또는 최근 성공 캐시에 의존한다.
- Claude 로컬 JSONL 로그는 토큰 사용량은 제공하지만 한도 대비 퍼센트는 제공하지 않으므로 정확한 fallback 퍼센트로 사용하지 않는다.
- 첫 Claude Keychain 접근 시 macOS 권한 허용 창이 뜰 수 있다.
- 현재 산출물은 로컬 개발용 unsigned `.app` 번들이다.

## 다음 개선 후보

- 로그인 항목 승인 상태를 System Settings로 바로 여는 버튼 추가
- 설정 창 분리
- provider별 enable/disable UI 추가
- signed/notarized 배포 빌드 구성
