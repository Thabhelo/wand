# Desktop acceptance — evidence through September 24, 2026

These records distinguish production-relay tests, local native actions and compatibility experiments. Input delivery alone is not a passing result. The owner confirmed Muse review submission on September 24, 2026; review approval remains pending. Muse web-to-Mac use has been tested, and a native Muse connection from the owner's account has worked since October 5 ([record](FIREBASE_CONNECTIONS.md#native-muse-connection-october-5)); its per-action evidence has not yet been added to this file.

## September 24: build 34 release results

Published **0.13.1 (34)** source `0d7960f` passed [CI run 35975546500](https://github.com/Thabhelo/wand/actions/runs/35975546500), including signing and notarization. App/DMG strict signatures, stapled tickets and Gatekeeper passed; DMG SHA-256 is `b0d2c1c060ce4f2a530bca7ff41d4aa16f4ba3db79e44b70dae0db358dccdf5f`. The exact app is installed at the existing path with owner team `58XWD3LBSS` and the same designated requirement. Unchanged-app restart, capture after restart and disposable-fixture cleanup also passed.

| Case | Current evidence | Result |
|---|---|---|
| Build 33 desktop and restart | Real TextEdit image; 45 typed lines independently checked through native accessibility; scrollbar moved from `1` to `0`; fresh image/text after confirmed quit/relaunch without a password | Pass on this installation; disposable fixture deleted and file absence verified |
| Final same-team build 34 update | Exact `0d7960f` CI app installed at `~/Applications/Wand.app`, unchanged designated requirement, automatic reconnect without a permission prompt | Pass on this installation |
| Final Safari capture | First image request `f3cce53a`, 08:33:42.467–08:33:43.221 UTC, returned a rendered image and Example Domain without manual window raising | Pass |
| Final TextEdit capture and input | First image request `81d41698`, 08:34:25.458–08:34:26.159 UTC, returned a complete 586 × 488 image; input `64439b8f`, 08:34:46.661–08:34:47.084 UTC, entered two test lines independently confirmed through native accessibility | Pass; disposable fixtures removed and absence verified |
| Final unchanged-app restart | Process exit confirmed, then automatic reconnect without Keychain or privacy prompts; first Safari image `9c685c88`, 08:36:47.937–08:36:48.705 UTC, returned Example Domain and a complete 640 × 357 image | Pass; native volume remained `100` |
| Native volume display | Final app showed `100`, matching actual dashboard volume `100`; no volume change performed | Display pass; not a drag/action regression test |
| Focus on/off | Build 33 dedicated controls succeeded; independent Control Center inspection verified Do Not Disturb on and then off; popover dismissed | Pass for this tested path |
| Safari pinned-tab cleanup | Candidate local command `bc1e8ce1`, `keep_pinned: true`, logged success from `07:55:58.737` to `07:55:59.768`; native inspection confirmed the disposable example tab gone, pinned tab retained and Safari's automatic Start Page | Pass for this local native path; not a relay/Muse result |
| Real relay lock | Candidate command `d299b81e` received `07:57:05.051`, succeeded `07:57:05.683`; dashboard showed Mac locked | Pass |
| Repeated real relay lock | `aee0e4ff` received `07:57:29.671`, succeeded `07:57:30.069`; dashboard reported already locked and minimal locked state was verified; owner later unlocked | Pass |
| Sleep request | `558c9e9a` accepted from `07:46:09.704` to `07:46:10.071`; `powerd` logged `SystemWillSleep` at `07:46:10.037` and display-off with `SoftwareSleep` | Sleep entry observed; immediate WindowServer trackpad activity woke the Mac within about a second; sustained sleep/offline and wake recovery not certified |
| Second sleep and reconnect test | `SystemWillSleep` at 03:06:50 local (08:06:50 UTC); actual sleep entry at 03:06:55.323; `SystemHasPoweredOn` at 03:07:38.109; dashboard afterward showed the Mac online with normal unlocked front-app state | Actual sleep of about 43 seconds and reconnect passed; owner confirmed manually waking the Mac, consistent with keyboard/UserActivity logs; 75-second missed-heartbeat/offline interval not observed live |
| Reviewer simulator reconnect | After the socket-race fix, status commands `1adaf22c` and `8500ab11` succeeded after reconnect and several minutes; page remained online | Retest passed; all task-created review devices revoked, with final revocation confirmed by the page and controls hidden |

The simulator also passed status, mute, unapproved-Shortcut rejection, approved synthetic Shortcut execution, offline rejection, reconnect, repeated lock, minimal locked state and rejection of mute while locked. These are hosted-flow results, not physical Mac execution. The timestamps above are recorded log times and command prefixes identify the test evidence without exposing device credentials.

Remaining checks include the 75-second missed-heartbeat/offline interval and recovery from it, a full reboot, and fresh-user or second-Mac installation with the current owner identity. No sustained 90-second sleep was demonstrated. The owner confirmed manually waking the Mac after about 43 seconds in the second sleep test. This matches the `MTP.DOCK.CHANNELS.AP0.IRQ` / `nub-spmi-a0.0x2B` and `RTP.keyboard/UserActivity` power-log entries. The manual wake ended the test before the longer offline interval could be measured; it is not evidence of an unintended wake or a Wand sleep failure. Chrome cleanup and Safari `keep_pinned: false` are not established by the pinned-Safari case. Native Muse authorization and tool/image compatibility still await verified client registration details. Earlier coverage below is retained as historical evidence, not a claim that every operation was retested on build 34.

Earlier unpublished build 34 candidates needed manual Safari window raising or returned `desktop_window_unavailable` on an initial request. The final artifact's first-request results above supersede those capture failures; they do not retroactively turn the earlier attempts into passes.

## Earlier app coverage retained from September 20–21

These production-relay results used earlier builds, principally 17–28, on macOS 26.6.2. They establish the listed operations only. The current build 34 checks are above; old preview publication status and completed implementation tasks have been removed.

| App or guard | Independently observed result |
|---|---|
| System Settings | Native controls and screenshot returned; Tab input changed the focused search field |
| Chrome | Disposable fixture reported coordinate-click success, exact typed text and Enter success; viewport visibly scrolled; build 28 repeated text replacement with a fresh image |
| Safari | Real window capture, fixture-confirmed coordinate click and visible scrolling |
| TextEdit | 45 lines, scrollbar change from `1` to `0`, Bold state change; later two-line replacement with a fresh image |
| Preview | Window capture, Zoom In, actual-size control and scrolling to earlier numbered image bands |
| Finder, build 24 | Image-based click selected only Test item 01; Right selected only Test item 02 |
| Dictionary, builds 24 and 28 | Search returned the telescope definition and a 512-pixel image after the earlier image-budget failure was fixed |
| Font Book, builds 25 and 28 | Replacing the search with Helvetica filtered to 2 of 362 typefaces |
| QuickTime Player, build 25 | Play/Pause advanced a silent disposable clip to 00:22 of 00:30 |
| Xcode, build 25 | A disposable editor buffer contained the exact replacement text and an Edited title; no code executed |
| Desktop stop, initial TextEdit test | Stop succeeded; subsequent observation returned `desktop_permission_required`, and native Wand showed desktop control off |
| Observation guards | Expired snapshots and changed app focus rejected input; current tests also cover ambiguous windows and changed window identity/geometry |

The [browser fixture](../tests/fixtures/desktop-browser.html) is served on localhost and has no accounts, persistence or network requests. Setup and independent inspection may use computer-control tools; the tested actions must go through Wand. Select the fixture physically before testing it: a background browser automation tab is not evidence that Wand targeted the intended window.

## Current implementation and regression references

[DesktopControl.swift](../agent/Sources/MacBridgeNative/DesktopControl.swift) contains bounded accessibility traversal, capture matching and guarded input. Images are resized to the 24 KB budget with encoded dimensions for coordinate conversion. Ambiguous windows fail closed. Input rejects stale observations and changed focus/window geometry; text entry goes through focused keyboard input, and web-area scrolling uses a guarded wheel path when appropriate. [Capture tests](../agent/Tests/MacBridgeNativeTests/CaptureTests.swift) and [window tests](../agent/Tests/MacBridgeNativeTests/ObservationWindowTests.swift) exercise the corresponding safeguards.

Lock, sleep, Safari/Chrome cleanup and Focus are implemented in [SystemActions.swift](../agent/Sources/MacBridgeNative/SystemActions.swift) and dispatched by [ActionExecutor.swift](../agent/Sources/MacBridgeNative/ActionExecutor.swift). [System-action tests](../agent/Tests/MacBridgeNativeTests/SystemActionTests.swift) cover confirmed lock results, pinned-tab classification and closure verification. The live evidence above distinguishes implemented behavior from verified paths: Chrome cleanup and Safari `keep_pinned: false` still lack equivalent physical acceptance. Focus currently matches the English Do Not Disturb description, so the recorded pass does not establish other locales.

The [current release note](RELEASE_0_13_1.md) identifies the signed artifact and release checks. [Permission lifecycle](PERMISSION_LIFECYCLE.md) records the signing-identity migration and repaired per-app permissions. Automated checks and notarization complement physical tests; neither establishes general app compatibility or native Muse integration.
