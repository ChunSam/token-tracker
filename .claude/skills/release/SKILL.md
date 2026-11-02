---
name: release
description: Token Tracker 새 버전을 릴리스하고 배포 산출물을 받아 설치·실행까지 확인한다. "릴리스해", "vX.Y.Z 내줘"에 발동한다.
---

# release

사용자가 릴리스를 지시했을 때만 머지·태그한다.

1. 버전 기본값 2곳 범프 → PR → CI 두 잡 초록 → `gh pr merge --rebase`.
2. 머지된 main 커밋에 `git tag -a vX.Y.Z` → push. `release.yml`은
   `gh run watch`를 백그라운드로 걸어 기다린다.
3. DMG와 `.sha256`을 새 디렉터리에 받아 그 자리에서 `shasum -c`. 마운트해 버전을 보고
   `scripts/verify_app_bundle.swift`로 검사한다.
4. 앱 종료 → 설치본을 휴지통으로 → `ditto`로 `/Applications`에 설치 → 실행 → 바뀐 화면 확인.

## Gotchas
- 상태 항목은 `/Applications`에서 실행할 때만 보인다.
- 종료 먼저. bundle id가 같아 나중에 뜬 쪽이 물러난다.
- `rm -rf`하지 않는다.
- `codesign -v`의 "not signed at all"은 정상(ad-hoc 서명은 실행 파일만).
- 바이너리 안 한국어는 `LC_ALL=C grep -a -F`로 찾는다. `strings`로는 안 잡힌다.
- 창은 `screencapture -l <windowID>`로 찍는다. `-R`은 겹친 다른 창을 찍는다.
