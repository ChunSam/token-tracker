# release — macOS 산출물 검사 세부

3·4단계에서 판정을 헷갈리게 했던 것들이다. 셋 다 실제로 한 번씩 물렸다.

- `codesign -v`가 "not signed at all"을 내도 정상이다. ad-hoc 서명은 실행 파일에만 붙고
  번들 전체에는 붙지 않는다. 번들 검사는 `scripts/verify_app_bundle.swift`가 맡는다.
- 바이너리에 새 한국어 문자열이 들어갔는지는 `LC_ALL=C grep -a -F '<문자열>' <실행 파일>`로
  찾는다. `strings`는 UTF-8 한국어를 잡지 못해 "없다"로 오판한다.
- 팝업·설정창은 `screencapture -x -o -l <windowID>`로 창 번호를 지정해 찍는다. `-R`(영역)은
  그 자리에 겹친 다른 창을 찍는다. 창 번호는 `CGWindowListCopyWindowInfo`에서 소유자
  `Token Tracker`로 찾는다(팝오버는 layer 25). 키체인 프롬프트의 소유자는 `SecurityAgent`다.
- 팝업은 computer-use로 보이지 않는다. System Events로 연다:
  `tell application "System Events" to tell process "TokenTrackerMenuBar" to click (first menu bar item of (last menu bar))`
  (1.2.0부터 숨은 편집 메뉴 때문에 메뉴 막대가 두 개이고, 상태 항목은 마지막 것에 있다.)
