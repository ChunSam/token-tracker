---
name: status
description: Token Tracker의 저장소·PR·릴리스·설치본·보류 항목을 훑어 남은 일을 보고한다. "상태 확인", "남은 작업 있는지 확인"에 발동한다. 인수인계 파일을 쓰거나 이어받는 것은 handoff다.
---

# status

읽기만 한다. 정리할 것은 목록으로 보여 주고 묻는다.

1. `git fetch --prune` 뒤 작업 트리·로컬/원격 브랜치·stash·worktree.
2. 열린 PR(자동 머지 여부)·이슈·최근 실패한 CI.
3. 미릴리스 커밋: `git log $(git describe --tags --abbrev=0)..origin/main`.
4. 설치본: `/Applications`와 VM의 버전 ↔ Latest 릴리스.
5. `.claude/handoff.md`, 직전 세션 트랜스크립트의 마지막 보고.
6. 보류·미검증: `grep -nE '보류|미검증|후속' docs/*.md WORK_SUMMARY.md`, 메모리의 재개 조건.

결론을 먼저 쓴다: 할 일 있음/없음 → 근거 → 정리 후보.

## Gotchas
- `--prune` 없이 보면 이미 지워진 원격 브랜치가 남아 보인다.
- 트랜스크립트의 "했다"는 성공의 증거가 아니다. 저장소와 대조한다.
- handoff.md가 없다고 쓰기 모드로 가지 않는다.
- VM이 꺼져 있으면 "확인 불가"로 적는다. `utmctl start`는 -1712로 실패한다.
