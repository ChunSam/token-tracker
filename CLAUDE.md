# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

이 파일은 120줄 이하로 유지한다. 넘치면 세부는 `README.md`(사용자 문서)와
`WORK_SUMMARY.md`(구현 요약)로 내린다.

## 저장소의 형태

Claude Code / Codex 사용량을 상시 표시하는 **macOS 메뉴바 앱(Swift)과 Windows 트레이 앱(C#)**,
두 개의 포트다. 로직은 `Sources/TokenTrackerCore/`와 `windows/TokenTracker.Windows.Core/`에
**파일 단위로 1:1 대응**하고, UI만 플랫폼별로 다르다(`TokenTrackerMenuBar/` ↔
`TokenTracker.Windows/`). Core 변경은 양쪽에 같이 넣고 양쪽 테스트에 같은 진리표를 추가한다.

Core는 순수 함수/타입이고 `now`를 주입받는다. HTTP·UI 하네스가 없어서, 그렇게 쓰지 않으면
테스트할 방법이 없다.

## 명령

```bash
swift build                                            # macOS 전체 빌드
swift run TokenTrackerSmokeTests                       # macOS 테스트 (통과 시 "TokenTrackerSmokeTests passed")
scripts/build_app.sh                                   # .app 조립 (APP_ARCHS="arm64 x86_64" 로 universal)
swift scripts/verify_app_bundle.swift ".build/Token Tracker.app"   # 조립된 .app 자체 검사
dotnet run --project windows/TokenTracker.Windows.Tests/TokenTracker.Windows.Tests.csproj
```

- **XCTest도 xunit도 없다.** 테스트는 실행 타깃 두 개(`Sources/TokenTrackerSmokeTests/main.swift`,
  `windows/TokenTracker.Windows.Tests/Program.cs`)의 top-level assertion 나열이고, 첫 실패에서
  종료한다. **테스트 하나만 고르는 수단이 없으므로**, 특정 assertion만 보려면 그 부분만 남기고
  임시로 잘라 실행한 뒤 되돌린다. `Tests/TokenTrackerCoreTests/`는 빈 잔재다.
- **이 개발 머신에는 dotnet이 없다.** Windows 코드의 컴파일 검증은 CI가 유일한 게이트다. C# 변경은
  작게 쪼개고, 과거 CI에서 터진 패턴(문자열 보간 안의 삼항 — `:`를 형식 지정자로 읽는다)을 피한다.
  CI가 초록으로 오기 전에 "동작한다"고 보고하지 않는다.
- Windows 테스트의 `now`는 `2026-05-27`로 고정돼 있다. 새 테스트는 자기 `now`를 주입한다.

## 데이터 흐름

`AppDelegate.startRefresh` / `TrayAppContext.RefreshAsync`가 주기적으로:

1. **제공자 클라이언트** — 저장된 토큰을 *읽기만* 한다. 갱신은 각 CLI(`claude`, `codex`)만 한다.
   그래서 요청 전에 만료를 먼저 판정하고(`CredentialExpiry`), 429는 지문에 묶인 쿨다운으로
   흡수한다(`RateLimitBackoff`/`RateLimitState`, 파일에 영속). 만료 토큰으로 요청하면 429가
   돌아와 백오프가 그것을 진짜 한도로 오해하므로, 만료면 요청 자체를 하지 않는다.
2. **`UsageSnapshotCachePolicy`** — 새 값을 못 얻은 제공자는 마지막 성공 값을 `staleCache`로
   유지한다(`staleToleranceHours`, 기본 12시간). 실패가 앱 종료나 빈 메뉴로 번지지 않게 하는 층이다.
3. **히스토리·알림·렌더** — 히스토리에는 `source == .api`인 실측값만 들어간다. 캐시 값은 추세·예측·
   스파크라인에 반영되지 않고 메뉴바 카운트다운도 붙지 않는다(값은 멈췄는데 시간만 흘러 틀린 시간이
   되기 때문). 이 불변식을 깨는 변경은 하지 않는다.

표시 규칙: 기본은 5시간 잔량, **7일 잔량이 10% 이하면 7일 값**을 대신 보여주고 강조색을 쓴다
(`DisplayFormatter.displayWindow` / `isSevenDayWarning`). 카운트다운은 그 값이 나온 창의 리셋을
가리켜야 한다 — 숫자와 시간이 다른 창을 가리키면 안 된다.

## 같이 바뀌어야 하는 것들

- **현지화**: 문자열 하나에 사전 **4개**(en/ko × macOS/Windows)와 키 enum 2개. macOS는 ko→en→키
  순으로 폴백하지만 **Windows는 한국어가 없으면 enum 이름을 그대로 노출한다**. 양쪽을 같이 채운다.
- **버전 기본값 2곳**: `scripts/build_app.sh`의 `APP_VERSION`/`APP_BUILD`,
  `windows/TokenTracker.Windows/TokenTracker.Windows.csproj`의 `<Version>`. CI가 드리프트를 막는다.
  릴리스 빌드는 태그와 run number로 덮어쓰므로 이 값들은 로컬 빌드용이다.
- **설정 키**: macOS `Settings`(UserDefaults)와 Windows `AppSettings`/`SettingsStore`(JSON)가 1:1이다.
  키 이름이나 저장 경로를 바꾸면 기존 사용자 설정의 마이그레이션을 먼저 판단한다.

## 릴리스 경로 — 소스 CI로는 보이지 않는 층

빌드가 통과하는 것과 배포된 파일이 동작하는 것은 다른 주장이다. 실제로 세 번 물렸다.

- **`Bundle.module`은 패키징된 `.app`에서 trap한다.** executable 타깃의 접근자는 실행 파일 번들 옆과
  컴파일 시점에 박힌 빌드 디렉터리만 보고, `Contents/Resources`는 후보에 없다. 빌드 머신에서는 그
  경로가 실재해 통과하므로 **로컬에서는 절대 재현되지 않는다.** 리소스는
  `StatusItemRenderer.resourceBundle`처럼 직접 찾는다.
- **체크섬 파일**은 파일명만 기록하고 LF로 끝내야 받은 자리에서 `shasum -c`가 통과한다.
- **Windows 어셈블리 버전**은 publish 플래그로 주입된다. 스탬프가 빠지면 진단이 `1.0.0`을 찍는다.

그래서 CI가 실제로 배포할 산출물을 조립해 검사하고(`verify_app_bundle.swift`, publish smoke,
버전 스탬프 확인), 릴리스 워크플로는 방금 쓴 체크섬을 그 자리에서 검증한다. **릴리스 후에는
산출물을 실제로 내려받아 설치·실행해 본다.**

릴리스 순서: 두 버전 기본값 범프 → PR 머지 → `git tag -a vX.Y.Z` → push → `release.yml`이 DMG·zip·
체크섬을 만들고 GitHub Release를 낸다.

## 작업 방식

`main`은 보호 브랜치다. 브랜치 → PR → CI 두 잡 초록 → **사용자의 명시적 승인("머지해") 후**
rebase 머지로 선형 히스토리를 유지한다. 커밋 메시지는 영어, PR 본문과 대화는 한국어다.

메뉴 폭은 긴 오류 문자열에 쉽게 밀린다. 새 행을 넣을 때는 짧게 쓰고, 길어지는 정보는 서브메뉴나
진단 텍스트로 내린다.
