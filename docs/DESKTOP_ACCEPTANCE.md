# Desktop acceptance — September 20, 2026

Meta submission remains on hold at the owner's request. These are Wand dashboard → production relay → installed Mac agent tests, not a real Muse integration test. Input delivery alone is not a passing result.

## Current live results

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
