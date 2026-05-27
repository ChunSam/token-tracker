# Token Tracker

macOS 메뉴바에서 Claude와 Codex의 사용량 잔량을 확인하는 작은 메뉴바 앱입니다.

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
- 7일 잔량 기준으로 표시 중인 퍼센트는 파스텔 레드로 강조
- 로그인 시 자동 실행 토글
- 라이트/다크 모드 메뉴 색상 대응
- Codex / Claude 연결 실패 시 잔량을 `--`로 표시

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
- 표시 방식
- 제공자 표기
- 제공자 활성화/비활성화
- 언어
- Windows 작업표시줄 아이콘 상시 표시 설정 열기
- 로그인 시 실행
- 종료

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

사용량 API 연결에 실패한 제공자는 잔량을 `--`로 표시합니다. 오래된 로컬 로그 값이 최신 잔량처럼 보이지 않도록 Codex도 연결 실패 시 `--`로 통일합니다.

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

생성 결과:

```text
windows/TokenTracker.Windows/bin/Release/net10.0-windows/win-x64/publish/TokenTracker.Windows.exe
```

### macOS 릴리즈 앱 번들 생성

```bash
scripts/build_app.sh
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
