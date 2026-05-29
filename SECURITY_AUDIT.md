# 보안 점검 및 하드닝 요약

## 목적

Token Tracker(macOS 메뉴바 · Windows 트레이 앱) 전체 코드베이스를 보안 관점에서 점검하고, 실질적 가치가 있는 하드닝을 적용한다.

## 점검 결과 총평

애플리케이션 코드의 실질적 위험은 **낮음**. 보안 기본기가 탄탄하다.

| 영역 | 평가 | 근거 |
| --- | --- | --- |
| 네트워크 | 양호 | `api.anthropic.com`, `chatgpt.com`로 **하드코딩된 HTTPS**만 사용. URL을 외부 입력으로 구성하지 않아 SSRF 없음 (`HTTPClient.swift`, `ClaudeUsageClient.swift:21`, `CodexUsageClient.swift:21`, `UsageClient.cs:7-8`) |
| 인증 토큰 전송 | 양호 | 토큰은 `Authorization: Bearer` 헤더로만 전송. 쿼리스트링 노출·로깅 없음 |
| TLS | 양호 | 인증서 검증 비활성화 없음(기본 `URLSession`/`HttpClient` 사용) |
| 파싱 | 양호 | `JSONSerialization` / `JsonDocument`로 안전 파싱. 임의 역직렬화·인젝션 벡터 없음 |
| 자격증명 | 양호 | macOS는 키체인 우선(`ClaudeUsageClient.swift:60`). 파일은 다른 앱(Claude Code/Codex)이 소유한 것을 **읽기만** 함 |
| 로그인 항목 | 양호 | 최신 `SMAppService` API 사용(`LoginItemManager.swift`) |

### 오탐 / 범위 외

- **Windows `homeDirectory` 경로 탐색** (`CredentialReader.cs`, `AppPaths.cs`): 기본값 `null`인 **테스트 전용 파라미터**로 공격자가 제어할 수 없음 → 오탐.
- **평문 자격증명 파일** (`~/.codex/auth.json`, `~/.claude/.credentials.json`): token-tracker가 생성/관리하지 않고 다른 앱이 소유한 파일을 읽기만 함 → 범위 외.

## 적용한 수정

### 1. Windows 릴리스 워크플로우 강화 — `.github/workflows/windows-release.yml`
- **최소 권한 토큰**: `permissions: contents: read` 블록 추가. 빌드 잡이 쓰기 가능한 기본 `GITHUB_TOKEN`을 상속하지 않도록 함.
- **무결성 검증**: 릴리스 zip의 SHA256 체크섬을 생성해 아티팩트에 함께 업로드. 다운로드 후 변조 확인 가능.

### 2. 방어적 파일 처리 하드닝
- **`Sources/TokenTrackerCore/CacheStore.swift`**: 캐시 디렉터리를 `0700`으로 생성하고, atomic write가 umask 기본값에 의존하지 않도록 매 저장 후 캐시 파일에 `0600` 재적용(소유자 전용).
- **`scripts/build_app.sh`**: 고정 경로 `.build/AppIcon.iconset`에 대한 `rm -rf` + `mkdir` 심볼릭 링크 경쟁 제거. `mktemp -d` 베이스 안에 `.iconset`을 생성하고 종료 시 `trap`으로 정리.

## 의도적으로 제외한 항목

| 항목 | 제외 사유 |
| --- | --- |
| Windows DPAPI 자격증명 암호화 | 앱이 자격증명을 **저장하지 않음**. 다른 앱 파일을 읽기만 하고 `settings.json`엔 표시 환경설정뿐이라 암호화 대상이 없음 |
| UI 에러 메시지 정제 | 로컬 단일 사용자 앱에서 같은 사용자에게 보이는 것이라 보안 이득 없음. 디버깅성만 저하 |

## 검증

- 워크플로우 YAML 파싱 통과.
- `build_app.sh` `bash -n` 문법 통과.
- `CacheStore.swift`는 표준 `FileManager` API 사용 — Swift 툴체인이 이 환경에 없어 컴파일 검증은 macOS에서 권장.
- 릴리스 워크플로우는 `workflow_dispatch` 수동 트리거. 다음 릴리스 실행 시 (1) read 권한으로 정상 완료되는지 (2) 아티팩트에 zip과 일치하는 `.sha256` 파일이 포함되는지 확인.

## 관련 PR

[#1 — Security hardening: CI supply chain + defensive file handling](https://github.com/ChunSam/token-tracker/pull/1)
