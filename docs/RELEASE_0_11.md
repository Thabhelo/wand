# Wand 0.11 — persistent desktop control

Owner-requested expansion: one-time local consent covers apps across the desktop, persists across relaunch and resumes after unlock. No app picker or 15-minute deadline in the normal UI. A menu-bar Pause disables it until locally enabled again; revocation also disables it. Existing 0.10 app grants never migrate silently.

System Settings and Terminal are now eligible. Known credential/security apps and Wand itself remain excluded. Observe may omit bundle_id to use the active app. Observations optionally include the app menu bar; window controls are the default to preserve the bounded observation budget. Added focused Unicode text entry, right/double clicks, Home/End/Page keys. Input still requires a fresh one-use observation, unlocked active session, and matching frontmost app/window. Screen Recording remains an owner-granted OS permission.

Muse chooses the steps. Ordinary navigation does not require per-step conversational approval; consequential operations still do. Protocol confirmation metadata and operator guidance express that distinction. No registered real Muse connection or completed Meta review is claimed.

The previous real TextEdit observe/type/press/stop test is documented in RELEASE_0_10.md. New 0.11 capabilities and persistent consent require separate physical validation; compile/unit tests do not prove general application compatibility.

## Validation on September 20
- 13 Swift, 32 relay, 19 contract and 7 website tests passed.
- Production OpenAPI exposes focused text entry and mouse-button/click-count parameters.
- Published 0.11 DMG SHA256 matches the local release.
- Owner enabled persistent desktop consent and Keychain access. A restart preserved consent.
- Live System Settings observation and window capture succeeded with build 14 after replacing stale macOS permission entries. PID-targeted mouse input reported delivery but did not navigate Settings; build 15 changes guarded mouse delivery to the HID event stream.
- Build 15: live System Settings accessibility observation succeeded after removing/re-adding Wand. Screen capture permission refresh and physical mouse navigation verification remain pending; input delivery is not proof that the target app reacted.
- Final published build 15 DMG SHA256: `4fc3b67ea6d08f3ea332d9bfdda1b1b9e7f208cb025274be045a92f514f51913`. Swift 13 and website 7 checks reran successfully after the final changes.

## Latest local validation

See DESKTOP_ACCEPTANCE.md for the current authoritative matrix. Development-signed build 17 is installed locally; Chrome screenshot, coordinate click, typing, Enter and scroll have passed through the production relay. System Settings observation, capture and Tab input also passed. These local fixes are not in the published build 15 DMG. Real Muse integration, broader native regression and public-distribution readiness remain open.

Build 17 is now published (September 21); the current download page points to it. See DESKTOP_ACCEPTANCE.md for checksum and expanded Safari/TextEdit results. New Keychain/system-action source is not in that artifact: the next signing attempt was cancelled at a Keychain authorization request.


The next candidate is 0.12.0 build 18, currently source-only with successful compilation and automated checks. It has not replaced the published build 17. See DESKTOP_ACCEPTANCE.md for the signing dependency and unverified dedicated actions.
