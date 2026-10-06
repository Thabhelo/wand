# Native Muse acceptance — October 5, 2026

October 5 native Muse custom Raw API testing passed OAuth PKCE S256, device/capability discovery, status, reversible volume and mute changes, app listing, Calculator open/focus/close/already-closed behavior, URL opening, TextEdit window images, pixel-coordinate clicking, typing, Return and scrolling. All 19 catalogued actions were authorized. Unsafe URL schemes, unallowlisted Shortcuts and invalid/consumed desktop snapshots were rejected. Authenticated reads succeeded beyond the stated 15-minute access-token lifetime without new consent; the refresh exchange itself was not visible. One status poll returned transient invalid_token and recovered by polling the same command, without resending it. Safari cleanup was inconclusive because the owner intentionally closed Safari during the test to free RAM. The owner confirmed lock and sleep work and requested no further disruptive retests. The owner subsequently reported the remaining checks passed on October 5: positive media playback, an allowlisted Shortcut, Focus and explicit reconnect. These are owner-verified passes, not independently observed native Muse executions. Desktop-stop restoration was not explicitly confirmed. This verifies a custom connector, not Meta directory approval.

## Execution evidence

| Check | Command / evidence | Outcome |
| --- | --- | --- |
| Volume + restore | 1bd1d2ac-df1c-4300-bcfb-f4cd187d9d9c; 27a7e113-5825-4deb-9607-6d824e951609 | 56 → 57 → 56, independently read back |
| Mute + restore | 77fd561f-c4c7-41c3-b8f8-3b237f093395; 62ba0f69-87c2-4f19-b70e-bd0a9166783a | false → true → false |
| App open/focus/close | ba9a4f5e-8a52-4617-a40d-9075e2f7f854; 59382c46-f59f-4219-8a72-0683255b0637; c3ce7a6a-c649-4d14-9583-5e9640149c88 | Calculator only; closed afterward |
| Already closed | 1b4389a0-1009-4f03-a84d-aedd486da5bb | succeeded, already_closed true |
| Window image | 2e7a723d-c735-4490-86f3-1cc2d2d216a9 | JPEG 586 × 488, visually inspected by Muse |
| Pixel click + insertion | e70c19cf-f5b6-49b5-862c-e2bf74b70bc7; 98f50b3f-b669-4384-82c7-8359f7772218 | Test line 15 click verified; independently inspected |
| Scroll | ac1991ae-80f1-4869-9582-f07d4c306919; 51295b46-0be2-4fcf-8034-eb0a47c03278 | Visible up/down movement |
| URL | 9d9ef1c8-9e91-4d67-b0d3-c15125485137 | Exact test tab verified and closed |
| Shortcut rejection | eddf8a59-6edf-4bd7-9153-b73ae8d3d673 | action_not_allowlisted |
| Safari | ad494313-2d84-4ea5-a7c5-60671e4798fd | browser_window_unavailable; owner closed Safari during test, inconclusive |
| Lock / sleep | Owner confirmation October 5 | Passed by owner; not rerun through this native session |

## Operator details

Coordinates are pixels within the returned image, not normalized coordinates. Obtain a fresh snapshot for each input: snapshots are consumed after use. Early out-of-bounds requests were rejected, then the corrected pixel click passed. Do not retry a write after a poll authentication error; poll the same command ID.

## Cleanup and retained evidence

Calculator and TextEdit were closed. The exact URL test tab was closed. The owner closed Safari. Original volume and mute state were restored. The useful test document is retained at `/Users/thabhelo/Documents/Playground/wand-muse-compatibility-2026-10-05/TextEdit-native-evidence.rtf`; it contains only numbered test lines. No private browser content was sent to Muse. No production configuration or permission reset was performed.
