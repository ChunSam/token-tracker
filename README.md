# Token Tracker

macOS 메뉴바와 Windows 시스템 트레이에서 Claude와 Codex의 사용량 잔량을 확인하는 작은 앱입니다.

## 주요 기능

- Claude / Codex 사용량 잔량을 메뉴바에 표시
- 5시간 / 7일 리셋 잔량과 리셋까지 남은 시간 확인
- 표시 방식 선택
  - `Lowest remaining`
  - `Claude + Codex`
  - `Codex only`
  - `Claude only`
- 제공자 표기 선택
  - `Cdx / Cl`
  - 공식 앱 아이콘 기반 표기
- 7일 잔량이 10% 이하일 때 7일 잔량을 우선 표시
- 표시 중인 창의 리셋까지 남은 시간을 메뉴바에 함께 표기 (설정에서 끄기 가능)
- 7일 잔량 기준으로 표시 중인 퍼센트는 파스텔 레드로 강조
- 로그인 시 자동 실행 토글
- 전용 앱 아이콘 포함
- 라이트/다크 모드 메뉴 색상 대응
- Codex / Claude 연결 실패 시 잔량을 `--`로 표시
- 저장된 액세스 토큰 만료를 미리 감지해 다시 로그인하라고 안내
- 오류 원인별 상태/복구 안내와 진단 정보 복사
- 낮은 잔량 및 리셋 임박 macOS/Windows 알림
- 최근 7일 로컬 히스토리 저장, 24시간 추세 표시, CSV 내보내기
- 설정 창에서 표시/제공자/새로고침/언어/알림/히스토리 옵션 관리

## 사용 방법

### 설치

GitHub Releases에서 최신 DMG를 다운로드합니다.

[Releases](https://github.com/ChunSam/token-tracker/releases)

DMG를 열고 `Token Tracker.app`을 `/Applications`로 복사한 뒤 실행합니다.

현재 배포 파일은 Apple 공증을 거친 빌드가 아니므로 다른 Mac에서는 Gatekeeper 경고가 뜰 수 있습니다. 임시로 실행해야 한다면 `/Applications`에 복사한 뒤 아래 명령을 실행합니다.

```bash
xattr -dr com.apple.quarantine "/Applications/Token Tracker.app"
open "/Applications/Token Tracker.app"
```

### 메뉴

메뉴바 항목을 클릭하면 다음 정보를 볼 수 있습니다.

- Claude 5시간 / 7일 잔량
- Codex 5시간 / 7일 잔량
- 각 리셋까지 남은 시간
- 데이터 출처
- 플랜 정보
- 오류 메시지
- 수동 새로고침
- 설정 창
- 진단 정보 복사와 인증 파일 위치 열기
- 히스토리 추세와 CSV 내보내기
- Windows 작업표시줄 아이콘 상시 표시 설정 열기
- 로그인 시 실행
- 종료

표시 방식, 제공자 표기, 제공자 활성화/비활성화, 새로고침 간격, 언어, 알림 기준, 히스토리 보관 기간은 설정 창에서 관리합니다.

## 퍼센트 표시 규칙

기본적으로 메뉴바에는 5시간 잔량을 표시합니다.

단, 7일 잔량이 10% 이하이면 7일 잔량을 대신 표시합니다.

예시:

| 5h | 7d | 메뉴바 표시 |
|---:|---:|---:|
| 100% | 90% | 100% |
| 100% | 42% | 100% |
| 100% | 10% | 10% |
| 100% | 0% | 0% |

7일 잔량이 표시되는 경우 해당 퍼센트는 파스텔 레드로 강조됩니다.

`메뉴바에 리셋까지 남은 시간 표시`를 켜면 퍼센트 뒤에 남은 시간이 붙습니다. 표시 중인 퍼센트와 같은 창의 리셋 시간이므로, 7일 잔량을 표시 중이면 7일 리셋까지의 시간이 나옵니다.

| 메뉴바 표시 | 의미 |
|---|---|
| `Cl 63% 2h13m` | 5시간 잔량 63%, 5시간 리셋까지 2시간 13분 |
| `Cl 8% 3d4h` | 7일 잔량 8%(우선 표시), 7일 리셋까지 3일 4시간 |
| `Cdx --` | 연결 실패 — 남은 시간은 붙지 않습니다 |

남은 시간은 사용량 새로고침과 무관하게 30초마다 갱신되므로, 새로고침 간격을 길게 잡아도 분 단위로 정확합니다.

사용량 API 연결에 실패한 제공자는 잔량을 `--`로 표시합니다. 오래된 로컬 로그 값이 최신 잔량처럼 보이지 않도록 Codex도 연결 실패 시 `--`로 통일합니다.

## 사용량을 못 불러올 때

Token Tracker는 각 CLI가 저장해 둔 액세스 토큰을 읽기만 하고, 직접 갱신하지 않습니다.
따라서 CLI를 한동안 쓰지 않아 토큰이 만료되면 잔량을 새로 가져올 수 없습니다.

토큰 수명은 제공자마다 다릅니다.

| | 액세스 토큰 | 재로그인 주기 |
|---|---|---|
| Claude | 약 8시간 | 약 30일 |
| Codex | 약 10일 | — |

Claude 쪽이 훨씬 짧습니다. 다만 **매번 다시 로그인할 필요는 없습니다** — 리프레시 토큰이 살아 있는 동안에는 Claude Code가 실행될 때 액세스 토큰이 자동으로 갱신됩니다. 즉 실제로 필요한 건 "한 달에 한 번 로그인"과 "가끔 Claude Code를 실행"입니다.

그 사이 공백은 마지막으로 성공한 값을 계속 보여주며 버팁니다. 유지 기간은 설정 창의 `마지막 값 유지 기간`에서 조절합니다(기본 12시간). 캐시된 값은 리셋까지 남은 시간을 표시하지 않고, 히스토리·추세·예측에도 반영되지 않습니다 — 실측값이 아니기 때문입니다.

메뉴의 `Status`가 `Sign in again` / `다시 로그인 필요`이면 해당 CLI에 다시 로그인한 뒤 새로고침합니다.

```bash
codex login
```

Claude는 `claude`를 실행한 뒤 `/login`을 입력합니다.

- Claude 토큰은 macOS 키체인(`Claude Code-credentials`) 또는 `~/.claude/.credentials.json`에서 읽습니다.
- Codex 토큰은 `~/.codex/auth.json`에서 읽습니다.

## 개발

### macOS 스모크 테스트

```bash
swift run TokenTrackerSmokeTests
```

### Windows 스모크 테스트

Windows 앱은 `.NET 10` 기반입니다. Windows 개발 환경에서 아래 명령으로 코어 로직 테스트를 실행합니다.

```powershell
dotnet run --project windows/TokenTracker.Windows.Tests
```

### Windows 앱 실행

```powershell
dotnet run --project windows/TokenTracker.Windows
```

Windows에서는 앱이 알림 영역 아이콘을 강제로 상시 표시하도록 설정할 수 없습니다. 우클릭 메뉴의 `Always Show Icon Settings...`를 눌러 Windows 작업표시줄 설정을 열고, 알림 영역/시스템 트레이 아이콘 목록에서 `Token Tracker`를 켜야 합니다.

### Windows 릴리즈 빌드

```powershell
dotnet publish windows/TokenTracker.Windows `
  -c Release `
  -r win-x64 `
  --self-contained true `
  /p:PublishSingleFile=true
```

ARM64 Windows용 빌드가 필요하면 `-r win-arm64`를 사용합니다.

생성 결과:

```text
windows/TokenTracker.Windows/bin/Release/net10.0-windows/win-x64/publish/TokenTracker.Windows.exe
```

`-r win-arm64`를 사용하면 같은 위치의 `win-arm64/publish` 아래에 생성됩니다.

### macOS 릴리즈 앱 번들 생성

```bash
scripts/build_app.sh
```

빌드 스크립트는 `Sources/TokenTrackerMenuBar/Resources/AppIcon.png`에서 macOS용 `AppIcon.icns`를 생성하고, 앱 번들의 `Info.plist`에 연결합니다.
기본값은 현재 Mac의 아키텍처로 빌드합니다. Intel/Apple Silicon 겸용 Universal Binary가 필요하면 아래처럼 실행합니다.

```bash
APP_ARCHS="arm64 x86_64" scripts/build_app.sh
```

생성 결과:

```text
.build/Token Tracker.app
```

### macOS 앱 실행

```bash
open ".build/Token Tracker.app"
```

## 배포 메모

호환성 있는 DMG를 만들 때는 HFS+ 형식을 사용합니다.

```bash
hdiutil create \
  -volname "Token Tracker" \
  -srcfolder ".build/Token Tracker.app" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "dist/TokenTracker-vX.Y.Z-macOS.dmg"
```

다른 Mac에서 일반적인 더블클릭 실행까지 안정적으로 지원하려면 Developer ID 코드 서명과 Apple notarization이 필요합니다.

## 프로젝트 구조

```text
.
├── Package.swift
├── Sources
│   ├── TokenTrackerCore
│   ├── TokenTrackerMenuBar
│   └── TokenTrackerSmokeTests
├── scripts
│   └── build_app.sh
├── windows
│   ├── TokenTracker.Windows
│   ├── TokenTracker.Windows.Core
│   └── TokenTracker.Windows.Tests
└── README.md
```
