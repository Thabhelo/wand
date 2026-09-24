# Desktop acceptance — evidence through September 24, 2026

The dated records below distinguish production-relay tests, local native actions and compatibility experiments. They do not establish registered native Muse integration. Input delivery alone is not a passing result.

## September 24: current release and candidate results

Public download remains **0.13.0 (33)**, Developer ID signed by the owner team `58XWD3LBSS` and notarized. A same-team **0.13.1 (34) candidate** is installed for testing; it is not published. The initial [build 34 CI run](https://github.com/Thabhelo/wand/actions/runs/35972120037), based on source `ccdba33`, passed signing and notarization. Publication is held while a window-focus repair and replacement artifact are completed.

| Case | Current evidence | Result |
|---|---|---|
| Build 33 desktop and restart | Real TextEdit image; 45 typed lines independently checked through native accessibility; scrollbar moved from `1` to `0`; fresh image/text after confirmed quit/relaunch without a password | Pass on this installation; disposable fixture deleted and file absence verified |
| Same-team candidate update | Build 34 requirement matches installed build 33; automatic connection without a new Keychain prompt; Safari screenshot after manually raising the window | Connection/capture observed; automatic window focus and final artifact verification pending |
| Focus on/off | Build 33 dedicated controls succeeded; independent Control Center inspection verified Do Not Disturb on and then off; popover dismissed | Pass for this tested path |
| Safari pinned-tab cleanup | Candidate local command `bc1e8ce1`, `keep_pinned: true`, logged success from `07:55:58.737` to `07:55:59.768`; native inspection confirmed the disposable example tab gone, pinned tab retained and Safari's automatic Start Page | Pass for this local native path; not a relay/Muse result |
| Real relay lock | Candidate command `d299b81e` received `07:57:05.051`, succeeded `07:57:05.683`; dashboard showed Mac locked | Pass |
| Repeated real relay lock | `aee0e4ff` received `07:57:29.671`, succeeded `07:57:30.069`; dashboard reported already locked and minimal locked state was verified; owner later unlocked | Pass |
| Sleep request | `558c9e9a` accepted from `07:46:09.704` to `07:46:10.071`; `powerd` logged `SystemWillSleep` at `07:46:10.037` and display-off with `SoftwareSleep` | Sleep entry observed; immediate WindowServer trackpad activity woke the Mac within about a second; sustained sleep/offline and wake recovery not certified |
| Reviewer simulator reconnect | After the socket-race fix, status commands `1adaf22c` and `8500ab11` succeeded after reconnect and several minutes; page remained online | Retest passed; all task-created review devices revoked, with final revocation confirmed by the page and controls hidden |

The simulator also passed status, mute, unapproved-Shortcut rejection, approved synthetic Shortcut execution, offline rejection, reconnect, repeated lock, minimal locked state and rejection of mute while locked. These are hosted-flow results, not physical Mac execution. The timestamps above are recorded log times and command prefixes identify the test evidence without exposing device credentials.

Remaining checks include the repaired candidate's automatic window focus and final signed artifact, sustained sleep/offline recovery, a full reboot, and fresh-user or second-Mac installation. Chrome cleanup and Safari `keep_pinned: false` are not established by the pinned-Safari case. Native Muse authorization and tool/image compatibility still await verified client registration details. Earlier dated results below remain historical evidence rather than new release claims.

## September 20 live results

| Case | Evidence | Result |
|---|---|---|
| Persistent desktop consent | Remained enabled through signed app updates/restarts | Pass |
| Reconnect | Last two signed updates reconnected without a visible new permission prompt; startup takes tens of seconds | Pass for these runs; startup latency needs improvement |
| Native observation | System Settings controls returned through production relay | Pass |
| Native screenshot | System Settings image returned after scoped ScreenCapture permission repair | Pass |
| Native keyboard | Tab delivered through Wand; native focused search field changed | Pass |
| Chrome observation | Disposable page fields and scroll target returned | Pass |
| Chrome screenshot | Actual test page image returned by ScreenCaptureKit through relay | Pass |
| Coordinate click | Clicking returned image dispatched Wand click; fixture changed to Coordinate click passed | Pass |
| Focused typing | Wand entered Wand keyboard test in the empty fixture field | Pass |
| Keyboard Enter | Fixture changed to Keyboard Enter passed: Wand keyboard test | Pass |
| Browser scroll | Corrected wheel path visibly moved viewport roughly 600 pixels down | Pass |
| Stale/focus guard | Expired observations and changed application focus rejected input during testing | Observed |
| Native coordinate navigation and native scrolling | No final successful independent verification | Pending |
| Real Muse phone-to-Mac loop | No verified registered client/callback or Muse tool/image integration | Pending |

Fixture: `tests/fixtures/desktop-browser.html`, served only on localhost. It has no accounts, persistence or network requests. Computer-use controls prepare the disposable test and inspect results; tested input is sent through Wand. Chrome must have the fixture physically selected, not merely bound as a background automation tab. This distinction caused early false starts.

## Fixes installed locally

Installed `/Users/Shared/Wand.app`: 0.11 build 17, Apple Development signed with the owner's Personal Team. Stable signing replaced ad-hoc signing; macOS permissions migrated once. The required public Apple WWDR intermediate was verified and added without trust overrides. No private key was exported. This is not notarized public distribution.

- Traverse empty accessibility containers without exhausting the 60-control output budget; bounded at 600 visited nodes and three seconds.
- Let ScreenCaptureKit enforce capture permission instead of rejecting through the legacy CoreGraphics preflight.
- Match screenshot windows by process and dimensions; prefer exact origin and accept a differing origin only for a unique candidate. Recheck focused window after capture. Ambiguity fails closed.
- Chrome can acknowledge native accessibility page scroll without moving. Web areas now use bounded wheel input at their visible center, with pointer placement and app hit checks. Native scroll areas retain native action with guarded fallback.

All 71 automated checks passed (Swift 13, relay 32, contracts 19, website 7). Swift 13 reran after the final scrolling change. Strict signature verification and git diff whitespace checks passed.

## Remaining gates

1. Broader native-app and browser regression coverage, including native coordinate navigation, scrolling, multiple windows/displays, pause, sleep/wake and reconnect.
2. Improve slow startup and the misleading unconditional Keychain-prompt message when no prompt exists.
3. Finish dedicated lock, sleep, pinned-tab browser cleanup and Focus actions; these remain unavailable in the preview.
4. Publish tested artifacts separately from this local development build. Public build 15 does not contain these latest fixes; notarized distribution remains separate.
5. Verify official Muse registration requirements, then run a real authorized phone-to-Mac workflow before submission. No Meta submission or review approval is claimed.

## September 21 release follow-up

Published the already-tested Apple Development-signed build 17 at `/releases/Wand-0.11.0-build17.dmg`. Downloaded production bytes match SHA256 `6d2b0327a412423ac07bfbad0c60f79efce9789ccd44b03ef2353bd97248995b`. Cloudflare website version: `2566ac48-ddc2-4a47-8a8c-bd29322cdc1d`. This supersedes the earlier statement above that build 17 is local only.

Additional live production-relay tests on build 17 passed:
- Safari window capture, coordinate click (fixture explicitly reported success), and visible scrolling.
- TextEdit multiline typing (45 numbered lines), native scrolling (scrollbar changed from 1 to 0), and native Bold activation (checkbox changed from 0 to 1).

A separate CUA compatibility spike, not a Wand action pass, confirmed Safari's `TabBarTab?isPinned=true/false` identifiers and close-tab accessibility action preserve a pinned fixture. Closing the last unpinned tab creates an empty Start Page; verification must check original target identities rather than require zero unpinned tabs.

### Prepared but NOT installed or published

The source now avoids rewriting an existing local API token and avoids reading bootstrap credentials once paired. Background startup disallows Keychain interaction; only an explicit Connect retry allows it. Legacy file-based items require the deprecated process-local interaction switch as well as LAContext. No keys are deleted or moved to plaintext storage. This behavior still needs signed-app validation.

Draft native operations now use a fixed Lock Screen shortcut with lock-state verification, IOPMSleepSystem request acknowledgement, guarded Safari tab cleanup, and Control Center accessibility for Focus. Lock/sleep were deliberately not exercised because they require the owner to unlock/wake the machine. Focus remains unverified. Chrome cleanup now has a draft implementation using its native Close Other Tabs menu, followed by closing a temporary blank tab; this implementation has not passed a live Wand test. Safari keep_pinned=false is not verified. Do not label these complete or release them before live verification.

New source compiles and 14 Swift tests pass; site tests remain 7/7. Signing the new binary requested access to the development private key. The codesign process was cancelled instead of asking the owner for another password or replacing the stable installed app with an ad-hoc build. The existing installed app and its permissions remain intact. Finishing these changes requires authorized use of the existing signing key; this is separate from granting Wand Accessibility or Screen Recording.

## Latest candidate — build 18, not released

The Chrome compatibility spike used an isolated window containing only disposable test tabs. Its native Tab → Close Other Tabs command preserved the pinned fixture and removed the other unpinned tab. This confirms menu behavior on this installed Chrome, not the draft Wand implementation or behavior on other versions/locales. The candidate UI now offers Safari and Chrome explicitly and confirms the selected browser before cleanup.

All 72 automated checks pass (Swift 14, relay 32, contracts 19, website 7). The build script now bounds signing to 60 seconds and removes incomplete staging on signing failure. A timed-out signing attempt left build 17 installed and published, with existing permissions unchanged. No password was automated and no permission reset was performed.

Build 18 still requires successful signing, installed-app startup/Keychain verification, and live dedicated-action tests. Lock/sleep testing also needs a person available to unlock/wake the Mac. Existing desktop-control results do not certify those dedicated actions. Do not publish the candidate as tested until these checks pass.

## September 21 live build 18 test

Build 18 signed successfully and was installed with the same designated requirement; desktop consent persisted and the app reconnected. iCloud had offloaded source files under Documents, causing packaging reads to hang. An archive of the committed source under /private/tmp/wand-local-source avoided that dependency.

The local Wand Lock control passed: command b4b5b358-c573-4eea-b526-124f7d99b70f was received at 15:54:38.982Z and succeeded at 15:54:39.178Z after lock-state verification; desktop access ceased. This was a local action test, not a Muse/relay dispatch test.

Focus failed with focus_control_unavailable. Safari cleanup reached execution but failed result validation (invalid_message); no visible tab closure was confirmed. Native non-state actions were returning result fields absent from ActionResult. The follow-up source returns the contract's empty acknowledgement for those actions and compiles; live retesting remains necessary. Sleep has not been tested. Build 17 remains the public download.

### Build 19 follow-up

Signed build 19 installed with the same identity. Safari cleanup passed locally: command 527a3d46-402d-444c-b522-3d6d67717a09 received at 16:00:47.247Z and succeeded at 16:00:47.885Z. CUA observed the two disposable unpinned tabs removed, the pinned fixture retained, and Safari's automatically generated Start Page. This verifies the response fix and pinned preservation on Safari 26.6.2. No relay or Muse claim is implied. Focus remains failed; Chrome cleanup and sleep remain untested.

### Build 21 Focus verification

Opened Control Center using CUA through System Settings > Menu Bar > Add Controls > Done. Observed controlcenter-focus-modes with a show-details action and the Do Not Disturb switch. Duration choices share the same identifier, so the implementation also matches the exact Do Not Disturb description. It traverses AXWindows as well as app children, opens the panel with Apple's documented Fn-C shortcut, and verifies the resulting switch value. This English-language description match remains a localization limitation.

Signed build 21 installed. Live local Focus-on command be42ed78-5727-4fc9-b04b-4da0f73687c4 succeeded at 16:12:11.752Z after receipt at 16:12:10.054Z; CUA independently observed Do Not Disturb on. Focus-off then completed and CUA observed Do Not Disturb off. Restored the original Work mode and verified Work on. This is local Wand verification, not Muse or remote relay verification. Sleep and Chrome cleanup remain untested. Public build remains 17.

Shortcut reference: https://support.apple.com/en-au/102650

## September 21 build 23 — additional live app coverage

Tested through the signed-in production desktop dashboard, production relay, and installed build 23 on macOS 26.6.2. Chrome Apple Events automation operated the dashboard DOM; it did not execute the tested native inputs directly. No credentials were exported. Fixtures were created under `/private/tmp/wand-app-compatibility`.

| App | Verified result | Remaining issue |
| --- | --- | --- |
| Preview | Real window screenshot; AXPress Zoom In visibly enlarged the numbered test image; actual-size control; scrolling returned the image from bands 8–12 to bands 1–5 | First observation during startup returned `desktop_window_unavailable`; later observations passed |
| Dictionary | Inspection and text replacement searched `butterfly`; a subsequent observation returned the search value, 13 results, and the dictionary definition | Capturing the populated result window failed with `desktop_image_too_large`; text-only observation worked |
| Finder | Captured the disposable 40-file folder and inspected its controls; click and Right-key commands acknowledged delivery | Click result did not match intended single-file selection, so coordinate accuracy is not certified. Later captures repeatedly failed with `desktop_capture_window_mismatch`; keyboard outcome was not visually certified |

These are bounded app-operation checks, not blanket compatibility certification. No Muse integration claim. Screenshot resizing/encoding limits and Finder window matching need follow-up; do not remove matching checks to turn these failures into apparent passes.

## September 21 compatibility fixes (candidates 24–28)

The failures above prompted implementation fixes, not just new coverage notes:

- Resize screenshot pixels as well as JPEG quality to stay within the 24 KB image budget; return the encoded dimensions for coordinate conversion.
- Exclude capture overlays, match the focused window by geometry/title, and reject ambiguous matches. Finder's desktop alone now reports that a window must be opened.
- Clear inherited input modifiers. Reject coordinate input if the observed window has moved or resized; reject any input if the focused window title changed.
- Replace editable text through focused keyboard input so native apps receive editing events. Chromium does not need a writable AXValue property; allow its focus action to settle before requiring exact-field focus.

Live checks through the production relay, using disposable fixtures:

| App | Result |
| --- | --- |
| Finder (24) | Screenshot confirmed a coordinate click selected only Test item 01; Right selected only Test item 02. |
| Dictionary (24) | Searching telescope returned its definition and a 512-pixel screenshot, replacing the previous image-too-large failure. |
| Font Book (25) | Replacing search with Helvetica filtered to 2 of 362 typefaces; setting AXValue alone previously left the list unchanged. |
| QuickTime Player (25) | Play/Pause advanced a silent disposable clip to 00:22 of 00:30, verified by fresh observation. |
| Xcode (25) | Replaced a disposable Swift editor buffer; fresh observation returned the exact test text and Edited title. No code executed. |
| TextEdit (25) | Replaced a disposable document with two lines; fresh observation returned both lines. |

Native tests: 16 passed, including noisy screenshot-budget/dimension tests and ambiguous-window rejection. Website tests: 7 passed. Earlier Chrome, Safari, System Settings and Preview results remain baseline evidence, not a claim that every operation in those apps was retested on the final candidate. Identical windows with indistinguishable geometry/title still fail closed. This is representative operation coverage, not certification of all Mac apps. Muse registration remains separate.

Final build 28 regression checks passed through the production relay: Chrome text replacement returned `Wand Chrome regression passed` in a fresh observation and screenshot; Font Book returned Helvetica and 2 of 362 typefaces; Dictionary returned telescope, its definition and a 512-pixel image; TextEdit returned the new disposable two-line content and a 640-pixel image. The installed signed binary and the DMG's signed binary have identical SHA256 `52891c300e39cd6ad91e86bfbc60ee9d093b7721b06753ed1b78b811f642fbdd`. The DMG passed integrity and strict code-signature checks. These updates reconnected without additional Wand permission approval; developer release signing needed one Keychain approval.

Published build 28 at https://getwand.app/releases/Wand-0.12.0-build28.dmg. Downloaded production bytes match SHA256 `b9fbbb34c5924adebdea716aa395b4f31a67933e54c67bdfbc661cdb1084e6b5`. Cloudflare website version: `c014edca-716a-4028-a2a1-a35953e898e8`. The public download page points to build 28. This remains an Apple Development-signed, non-notarized beta.
