# Token Tracker

macOS 메뉴바와 Windows 시스템 트레이에서 Claude와 Codex의 사용량 잔량을 확인하는 작은 앱입니다.

## 주요 기능

- Claude / Codex 사용량 잔량을 메뉴바에 표시
- 5시간 / 7일 리셋 잔량과 리셋까지 남은 시간 확인
- 표시 방식 선택
  - 가장 낮은 잔량 (`Lowest remaining`)
  - `Claude + Codex`
  - Codex만 (`Codex only`)
  - Claude만 (`Claude only`)
- 제공자 표기 선택
  - `Cdx / Cl`
  - 공식 로고 (앱 아이콘 기반 표기)
- 7일 잔량이 10% 이하일 때 7일 잔량을 우선 표시
- 표시 중인 창의 리셋까지 남은 시간을 메뉴바에 함께 표기 (설정에서 끄기 가능)
- 7일 잔량 기준으로 표시 중인 퍼센트는 파스텔 레드로 강조
- 로그인 시 자동 실행 토글
- 전용 앱 아이콘 포함
- 라이트/다크 모드 메뉴 색상 대응
- Codex / Claude 연결 실패 시 잔량을 `--`로 표시
- 저장된 액세스 토큰 만료를 미리 감지해 다시 로그인하라고 안내
- Claude 토큰이 만료되면 Claude Code를 잠깐 실행해 갱신 (설정에서 끄기 가능)
- 오류 원인별 상태/복구 안내와 진단 정보 복사
- 낮은 잔량, 리셋 임박, 수집 중단, 다시 사용 가능 macOS/Windows 알림
- 창마다 균등 사용선 대비 페이스(빠름·적정·여유) 표시
- Claude 추가 사용량이나 Codex 크레딧을 쓰는 계정은 카드에 금액 표시 (구독만 쓰면 표시 없음)
- API를 쓴 만큼 내는 조직은 Admin 키로 이번 달 사용 금액·오늘·상위 모델·월 예산 대비 표시 (켜야 동작)
- 하루 한 번 새 버전 확인 (설정에서 끄기 가능)
- 잠자기에서 깨어나면 바로 새로고침
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

### 메뉴바 팝업

macOS에서 메뉴바 항목을 클릭하면 팝업이 열립니다.

- 제공자별 카드: 5시간 / 7일 잔량 막대, 각 리셋까지 남은 시간, 상태(정상·상태줄·캐시·오류), 플랜
  - 잔량이 설정한 알림 기준 이하이면 막대가 주황색, 10% 이하이면 빨간색
  - 문제가 있으면 원인, 복구 방법, 기술 오류를 카드 안에 표시
  - Claude 추가 사용량이 켜진 계정은 `추가 사용량 $1.86 / $5.00`과 한도 대비 막대(80% 이상 주황,
    100% 이상 빨강), Codex 크레딧이 있는 계정은 `크레딧 잔액 18.40`(달러가 아닌 크레딧 수). 둘 다 없는
    계정의 카드는 그대로입니다. 메뉴바에는 금액을 쓰지 않습니다
  - API 비용을 켜고 Admin 키를 넣은 제공자는 `이번 달 사용 $42.18`, 월 예산이 있으면 `예산 $100 중 42%`와
    막대(80% 이상 주황, 100% 이상 빨강), `오늘 $3.07 · Opus 5.5 71% · Sonnet 5.5 27%`, Claude는 데이터가
    반영된 시각(`14:20 기준`)까지 표시합니다. 구독 한도를 끈 제공자는 카드가 금액만으로 이루어집니다
- 페이스와 소진 예측 (설정의 `소진 예측 표시`를 켠 경우)
  - 막대 위의 눈금은 창을 리셋까지 고르게 쓸 때 지금 남아 있어야 할 위치입니다. 채움이 눈금보다
    짧으면 고르게 쓸 때보다 빨리 쓰고 있다는 뜻입니다
  - `페이스: 5h 빠름 · 7d 적정`은 그 차이가 10%p를 넘는지로 정합니다. 캐시 값에는 붙지 않습니다
- 새 버전이 나와 있으면 맨 위에 `새 버전 vX.Y.Z` 줄과 다운로드 링크(릴리스 페이지)
- 하단: 마지막 업데이트 시각, 새로고침(⌘R), 설정(⌘,), 더 보기(`⋯`)
- `⋯` 메뉴: 업데이트 일시중지, 히스토리 추세와 CSV 내보내기, 진단 정보 복사와 인증 파일 위치 열기,
  로그인 시 실행, 종료

Windows에서는 트레이 아이콘의 메뉴에 같은 정보(잔량, 리셋, 추가 사용량·크레딧, API 비용, 데이터 출처, 플랜, 오류)와
작업표시줄 아이콘 상시 표시 설정이 들어 있습니다.

표시 방식, 제공자 표기, 제공자 활성화/비활성화, 새로고침 간격, 언어, 업데이트 확인, 알림 기준, 히스토리 보관 기간은 설정 창에서 관리합니다.

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

Windows 트레이에는 텍스트를 놓을 자리가 없어(아이콘에 퍼센트를 그려 넣습니다) 같은 정보가
**툴팁**으로 갑니다 — `툴팁에 리셋까지 남은 시간 표시`를 켜면 `Cdx 91% 42m, Cl 63% 2h13m`처럼
보입니다. 창을 고르는 규칙과 캐시된 값에는 시간을 붙이지 않는 규칙은 양쪽이 같은 Core 함수를
씁니다.

| 메뉴바 표시 | 의미 |
|---|---|
| `Cl 63% 2h13m` | 5시간 잔량 63%, 5시간 리셋까지 2시간 13분 |
| `Cl 8% 3d4h` | 7일 잔량 8%(우선 표시), 7일 리셋까지 3일 4시간 |
| `Cl 100%` | 5시간 창이 아직 열리지 않음 — 가리킬 리셋이 없어 시간이 붙지 않습니다 |
| `Cdx --` | 연결 실패 — 남은 시간은 붙지 않습니다 |

Claude의 5시간 창은 **첫 사용 때 열립니다.** 창이 없는 동안 API는 잔량(100%)은 주지만 리셋
시각을 주지 않으므로, 메뉴바에는 퍼센트만 뜨고 팝업(Windows는 메뉴)의 5시간 리셋은 `아직 없음(첫
사용 시 시작)`으로 표시됩니다. 값을 못 읽었다는 뜻의 `--`와는 다릅니다.

제공자가 응답은 했는데 그 안에 5시간 창이 아예 없으면 — 예를 들어 인증된 Claude Ultra 계정 —
5시간 리셋은 `제공되지 않음`으로 표시됩니다. 이것 역시 읽기 실패가 아니라, 받은 응답에 그
창이 없었다는 뜻입니다.

남은 시간은 사용량 새로고침과 무관하게 30초마다 갱신되므로, 새로고침 간격을 길게 잡아도 분 단위로 정확합니다.

사용량 API 연결에 실패하면 설정한 유지 기간 안의 마지막 측정값을 캐시로 표시합니다. 유효한 캐시가 없거나 기간이 지나면 Claude와 Codex 모두 `--`로 표시합니다.

## API 비용 (Admin 키)

Claude Code나 Codex를 API 키로 쓰면 구독 한도가 없어서 카드에 `로그인 필요`와 `--`만 남습니다. 이때는 조직의
Admin 키로 이번 달 사용 금액을 볼 수 있습니다. 구독 한도와 조직 API 비용을 함께 볼 수도 있습니다.

1. Admin 키를 만듭니다. 이 앱 전용으로 새로 만드는 것을 권합니다.
   - Anthropic: [Console › Admin keys](https://platform.claude.com/settings/admin-keys)에서 `sk-ant-admin…` 키.
     개인 계정에는 없고 조직이 있어야 합니다. 만료일을 걸어 두세요.
   - OpenAI: [Admin keys](https://platform.openai.com/settings/organization/admin-keys)에서 `sk-admin-…` 키.
     조직 Owner만 만들 수 있습니다. 프로젝트 키(`sk-proj-…`)로는 비용을 읽을 수 없습니다.
2. 설정 창의 Claude 또는 Codex 칸에서 `API 비용 (Admin API)`를 켜고 `Admin 키…`에 붙여넣습니다. 키는 macOS
   키체인(Windows는 DPAPI로 암호화한 파일)에만 저장되고, 진단 정보에는 끝 4자리만 나옵니다.
3. 필요하면 `월 예산`(USD)을 넣습니다. 0이면 예산 막대가 없습니다.

- 비용은 10분마다(실패하면 5분 뒤) 따로 조회합니다. 실패하면 같은 달 안에서는 마지막 값을 `캐시 데이터 사용 중`으로
  보여줍니다. 키가 거부되면 `Admin 키 거부됨`이 뜹니다.
- Anthropic 비용은 보통 4시간, 길게는 24시간 늦게 반영됩니다. 그래서 `14:20 기준`처럼 반영 시각을 함께 보여주고,
  오늘 몫이 아직 없으면 `집계 전`이라고 씁니다. `이번 달`과 `오늘`은 기기 시간대 기준이라 청구서(UTC 달)와 달
  경계 부근에서 몇 시간분 다를 수 있습니다.
- 구독 한도를 끄고 API 비용만 켠 제공자는 메뉴바에 이번 달 금액을 씁니다(`Cl $42`). 구독 한도가 켜진 제공자는
  메뉴바에 퍼센트를 그대로 씁니다. Windows 트레이 아이콘은 구독 한도가 모두 꺼졌을 때 `$`를 그립니다.
- macOS: 이 앱은 ad-hoc 서명이라 업데이트 뒤 처음 키를 읽을 때 키체인 접근을 허용할지 한 번 묻습니다.

## 사용량을 못 불러올 때

Token Tracker는 각 CLI가 저장해 둔 액세스 토큰을 읽기만 하고, 직접 갱신하지 않습니다.
따라서 CLI를 한동안 쓰지 않아 토큰이 만료되면 잔량을 새로 가져올 수 없습니다.

### Claude 토큰 자동 갱신

Claude 토큰이 만료돼 있으면 Token Tracker가 설치된 Claude Code(`claude`)를 잠깐 실행합니다.
Claude Code는 시작하자마자 저장된 토큰을 스스로 갱신하므로, 그 뒤 다시 읽으면 잔량을 가져올 수
있습니다. 터미널에서 `claude`를 한 번 실행하는 것과 같은 일이고, 데스크톱 앱만 쓰는 경우에도
토큰이 유지됩니다. 설정의 `Claude Code로 토큰 자동 갱신`으로 끌 수 있습니다(기본 켬).

- 앱이 리프레시 토큰을 직접 쓰지 않습니다. 리프레시 토큰은 한 번 쓰면 바뀌므로 앱이 쓰면 CLI가
  로그아웃되고, Anthropic 약관도 서드파티 앱이 Claude 자격 증명을 다루는 것을 금합니다. 수정되지
  않은 CLI가 자기 방식대로 갱신할 뿐입니다.
- 실행은 Claude Code가 신뢰한 적 없는 앱 전용 폴더에서 하고, 훅·MCP 서버·Remote Control을 끄는
  옵션을 붙입니다. 그래서 신뢰 확인 화면에서 멈추며 훅, 플러그인, 세션 기록이 생기지 않습니다.
  모델 요청도 하지 않아 사용량을 쓰지 않습니다. 화면에는 아무것도 뜨지 않습니다.
- 갱신에 성공하면 5분, 저장소가 그대로였거나 CLI를 못 찾으면 30분 동안 다시 시도하지 않습니다.
  저장소가 그대로라면 리프레시 토큰까지 만료된 것이니 터미널에서 `claude` 실행 후 `/login`이
  필요합니다.
- macOS는 `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, PATH 순으로
  `claude`를 찾습니다. Windows는 `%USERPROFILE%\.local\bin\claude.exe`와 PATH의 `claude.exe`만
  씁니다(npm 설치의 `.cmd`는 쓰지 않음).
- `진단 정보 복사`에 `Claude CLI renewal`(설정), `Claude CLI`(찾은 경로), `Claude CLI last renewal`
  (마지막 시도 시각과 결과)이 들어갑니다.

Claude 토큰의 만료 여부는 저장된 `expiresAt`을 기준으로 판단합니다. 앱이 읽는 인증 저장소에 유효한 토큰이 있어야 하므로 다른 클라이언트에서 로그인하는 것만으로 복구된다고 보장할 수는 없습니다. Claude Code 자체도 로그인을 더 이상 갱신할 수 없으면 `/login`이 필요합니다. [공식 인증 문서](https://code.claude.com/docs/en/authentication#renew-an-expiring-login)

토큰이 만료되고 인증 저장소도 오랫동안 갱신되지 않았다면, 팝업(Windows는 메뉴)의 Claude 항목에 `자격 증명이 2d 3h째 갱신되지 않음`처럼 경과 시간이 함께 표시됩니다. 이 경우 터미널의 Claude Code에서 로그인 상태를 확인합니다.

`진단 정보 복사`에는 `Claude credential source`(keychain/file)와 `Claude credential age`가 상태와 무관하게 항상 포함됩니다.

그 사이 공백은 마지막으로 성공한 값을 표시합니다. 유지 기간은 설정 창의 `마지막 값 유지 기간`에서 조절합니다(기본 12시간). Claude와 Codex 각각의 실제 측정 시각부터 계산하며, 실패한 재조회나 앱 재실행으로 연장되지 않습니다. 이전 버전 캐시는 측정 시각을 신뢰할 수 없어 한 번 폐기하며, 다음 조회 성공 시 다시 저장합니다. 캐시된 값은 리셋까지 남은 시간을 표시하지 않고, 히스토리에는 새 측정값으로 추가하지 않습니다.
캐시된 값이 폴링 3회(최소 30분)보다 오래되면 `사용량 갱신 멈춤` 알림이 제공자별로 한 번
갑니다 — 그럴듯해 보이는 숫자가 조용히 낡아가는 것을 눈으로 발견해야 하지 않도록. 다시
측정되면 알림이 재무장되고, 보여줄 값이 아예 없어 `--`인 경우는 알리지 않습니다. 그 표시는
살아 있는 값으로 오해할 수가 없기 때문입니다.

알림 기준 이하로 떨어졌던 창이 리셋된 뒤 다시 측정되어 기준을 넘으면 `다시 사용 가능` 알림이 한 번
갑니다. 마지막 값은 앱을 껐다 켜거나 토큰이 만료된 동안에도 유지되므로, 그 사이에 지난 리셋도
다음 측정 때 알려줍니다. 알림 기준을 0으로 두면 이 알림도 꺼집니다.

`리셋 임박` 알림은 리셋 때 그냥 사라질 양이 있을 때만 갑니다. 잔량이 그 창의 알림 기준보다 많아야
하고, 본문에 남은 양을 적습니다(`Claude 5h 5m 후 리셋 — 60% 남음`). 이미 기준 이하인 창은 리셋이
반가운 소식이라 알리지 않고, 리셋 뒤 `다시 사용 가능` 알림이 갑니다. 캐시된 값으로는 보내지 않습니다.

새 버전 확인은 하루 한 번(실패하면 한 시간 뒤) GitHub Releases API에 최신 릴리스를 묻습니다.
사용량 제공자 말고 앱이 보내는 유일한 요청이며, 설정의 `업데이트 확인`으로 끌 수 있습니다.
자동 설치는 하지 않고 릴리스 페이지만 엽니다.

Claude나 Codex의 상태가 `Saved token expired` / `저장된 토큰 만료`이면 해당 CLI의 토큰을 갱신한 뒤 새로고침합니다.

```bash
codex login
```

Claude는 자동 갱신이 켜져 있으면 대개 직접 할 일이 없습니다. 꺼 두었거나 갱신이 실패했다면
`claude`를 한 번 실행하면 됩니다. 액세스 토큰은 약 8시간, 리프레시 토큰은 약 4주를 살기 때문에
실행만으로 CLI가 저장된 토큰을 갱신합니다 — 대개 재로그인은 필요하지 않습니다. 그래도
`저장된 토큰 만료`가 남으면 그 안에서 `/login`을 입력합니다.

- Claude 토큰은 macOS 키체인(`Claude Code-credentials`) 또는 `~/.claude/.credentials.json`에서 읽습니다.
- Codex 토큰은 `~/.codex/auth.json`에서 읽습니다.

### 상태줄 브리지 — 토큰이 만료돼도 Claude 잔량 보기

Claude Code 상태줄은 세션에 5시간/7일 사용률을 그대로 넘겨줍니다. 그 숫자만 로컬 파일로 받아오면
저장된 토큰이 만료돼 있어도 Claude 잔량을 표시할 수 있습니다. 설정은 기존 상태줄 명령을 `--` 뒤에
적어 감싸는 것뿐이고, 상태줄 출력은 그대로 유지됩니다. Claude Code 2.1.251 이상이 필요합니다.

`~/.claude/settings.json` (macOS):

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/path/to/Token tracker/scripts/claude-statusline-bridge.sh\" -- node /your/statusline.js"
  }
}
```

`%USERPROFILE%\.claude\settings.json` (Windows):

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\path\\claude-statusline-bridge.ps1\" -- node C:\\your\\statusline.js"
  }
}
```

파일에는 사용률 두 개, 각 창의 리셋 시각, 측정·기록 시각만 들어갑니다. 토큰이나 세션 페이로드는
저장하지 않습니다. 설정하지 않으면 동작은 전혀 바뀌지 않습니다.

상태줄 명령이 타이머로 다시 실행되는 것은 새 측정이 아니므로, 숫자가 바뀌지 않은 재실행은 측정
시각을 밀지 않습니다. 측정 후 30분이 지난 값은 `캐시 데이터 사용 중`으로 내려가고, 유지 기간이
지나면 `--`가 됩니다. 상태줄 값은 히스토리·추세·예측에는 들어가지 않습니다 — 그쪽은 앱이 직접
측정한 값만 받습니다. 형식과 설계 근거는 [상태줄 브리지](docs/claude-statusline-bridge.md),
장기 인증 조사는 [Claude 사용량 수집 조사](docs/claude-usage-auth.md)에 있습니다.

CLI를 띄워 두지 않거나 다른 기기에서만 사용하면 브리지도 현재 사용량을 알 수 없습니다. 상시
백그라운드 수집을 대신하지는 못합니다.

브리지를 채우는 것은 **상태줄을 실행하는 세션**이고, 이는 "Claude Code 세션"보다 좁습니다.
데스크톱 앱의 Claude Code는 브리지를 채우지 않습니다 — 브리지를 설치한 채로 데스크톱 세션이
활발히 요청하는 180초 동안, 그리고 그 앞 9시간 동안 `written_at`이 전혀 움직이지 않았습니다.
채우는 것은 터미널 CLI이며, 그 세션의 첫 API 응답 뒤부터입니다. 진단 정보의
`Claude status line record: none`이 바로 그 상태입니다.

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

Apple Silicon Mac에서는 UTM의 Windows 11 Arm 가상 머신으로 테스트·빌드·실행을 할 수 있습니다.
설정과 Mac에서 가상 머신을 다루는 방법은 [Windows VM 테스트](docs/windows-vm-testing.md)에 있습니다.

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

버전은 태그(`v1.1.6`)에서 나옵니다. 릴리스 빌드는 macOS는 `APP_VERSION`, Windows는 `/p:Version`을 태그에서 받고, 빌드 번호로는 workflow run number를 씁니다. 로컬 빌드가 쓰는 기본값은 두 곳에 있으므로 버전을 올릴 때 함께 고칩니다 — `scripts/build_app.sh`의 `APP_VERSION`/`APP_BUILD`, `windows/TokenTracker.Windows/TokenTracker.Windows.csproj`의 `<Version>`.

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
│   ├── build_app.sh
│   ├── claude-statusline-bridge.ps1
│   └── claude-statusline-bridge.sh
├── windows
│   ├── TokenTracker.Windows
│   ├── TokenTracker.Windows.Core
│   └── TokenTracker.Windows.Tests
└── README.md
```
