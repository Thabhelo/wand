# Current hosted status

See [Wand launch status](../deploy/WAND_LAUNCH.md) for the current Cloudflare deployment and sign-in blocker. The entries below are chronological history and do not override the current status.

# Connected build status — 2026-09-20

## Implemented
- Shared schema-validated REST/device protocol and closed action catalog.
- FastAPI relay: Auth0 JWT validation, two-authority pairing/redemption, hashed device tokens, in-memory WebSockets, generation fencing, heartbeats, result polling/timeouts, ownership checks, rate limits, redacted audits, device/account revocation and active-data deletion.
- SQLite behind a repository boundary, single-process deployment configuration, Docker/Fly recipe and Render guidance.
- Web dashboard with Auth0 sign-in, pairing, device status/rename/revoke and data deletion.
- Separate MacBridge Swift app with real HTTPS pairing, Keychain credentials, WSS reconnect/heartbeat, session fencing, local forensic logs, allowlist settings, offline-revoke warning and loopback bearer API.
- Native execution implementations for URL/app opening, graceful app quit, allowlisted Shortcut invocation, volume/mute, supported media controls and minimized device state. These use an explicit OS lock flag plus matching active-session ownership checks. A native read-only execution has passed; physical control behavior remains unverified.
- OpenAPI generated from canonical contracts, internal action manifest, operator instructions, security/privacy/terms drafts, demo script and clearly labeled loopback reviewer sandbox.

## Explicitly incomplete
- The active/unlocked case now passes using IOConsoleLocked and two matching session-ownership checks. This OS implementation property is undocumented, and actual lock/unlock transitions and macOS 27 runtime behavior still require verification. Missing, malformed or conflicting signals fail closed.
- Real lock invocation, pinned-tab handling, Focus/DND changes and sleep/wake behavior need empirical implementation/verification; these return specific errors.
- Now-playing readout is currently null. Media player selection currently prioritizes a running Music process before Spotify; active playback preference needs verification.
- Hosted Auth0 configuration, TLS deployment/domain, platform connector import format and phone-to-Mac run are not configured/verified.
- Offline local revoke remains blocked until the user explicitly confirms completing dashboard revocation. This is a user acknowledgment, not independently verified server evidence.
- Agent token rotation is revoke/re-pair, not seamless rotation. Bootstrap recovery across agent restart needs further hardening.
- Signed/notarized distribution requires the owner's Apple Developer identity. The local packaged build is ad-hoc only.
- Real demo video and externally accessible reviewer sandbox have not been produced/deployed.
- Backup deletion replay and hosted identity deletion are not implemented. Data deletion covers active MacBridge application records.

The build is not a finished MVP and must not be presented as such. Tests establish protocol behavior, not physical Mac actions or Meta acceptance.

## Verification in this build
- 38 Python tests passed, including RSA JWT rejection cases, real relay integration, shared contracts and Swift protocol-peer checks.
- 6 Swift native tests passed, including loopback bearer authentication, browser-origin rejection and unsafe executor input rejection.
- Swift app build succeeded; ad-hoc packaging and strict code-signature verification passed at `/private/tmp/macbridge-test-session-20260920/MacBridge.app`.
- The reviewer sandbox's browser get_state command visibly reached `succeeded` through the real relay. A later browser-native confirmation dialog stalled the computer-use tool; simulated lock was not counted as a completed browser test.
- No physical lock/sleep/tab-close/quit/Shortcut action was executed on the main Mac session. No hosted deployment, notarization or Meta submission occurred.


## Update: real native state read (2026-09-20, 12:20 local)
- Added LockStateReader with strict CFBoolean handling, current UID matching, exactly-one-active-console validation and conflict rejection. No missing-key default to unlocked.
- Replaced the hardcoded unknown state in agent/local request paths. get_state checks again after collection to avoid releasing a snapshot after locking or switching users.
- Added Read this Mac to the real app, using its production command/log path. It does not require relay enrollment.
- NativeStateProbe and the live XCTest executed the actual native get_state implementation on the current Mac: valid schema, screen_locked:false, battery present, four running app names collected (names not printed or saved in evidence).
- Eight Swift tests passed, including fail-closed lock-signal cases and the live read-only test. No physical control action ran. Earlier Python results were not rerun because relay/contracts were unchanged.
- App 0.4.0 is packaged and signature-verified at /Users/Shared/MacBridge.app. Atomic bundle replacement avoids overwriting a running executable. Existing processes must reopen to load the update.
- Computer-use launched the app process but its accessibility inspection timed out twice. A stack sample showed the normal application event loop. Therefore button-click/visual verification is still not claimed; the native execution path was verified independently.


## Update: installed native window repaired (0.5.0)
- Replaced the SwiftUI scene/window lifecycle with an explicit AppKit application delegate, NSWindow and standard target/action controls. Finder reopen raises the existing window.
- Installed app visibly displayed actual battery/frontmost/running-app information and `Read this Mac — succeeded` during computer-use verification. This supersedes the previous unverified-button limitation.
- Added local Calculator launch, mute/unmute, volume and HTTP(S) website controls with visible progress/outcome text. They use the existing schema-validated, logged, lock-guarded native command path. The real local API separately returned HTTP 200 with a state result.
- The local audit recorded open_app received/succeeded during UI testing; Calculator's continued running state was not confirmed. Audio unmuted feedback was visible while the user was interacting; this is not an acoustic measurement.
- Existing main-user development instance was stopped for installation, preserving Keychain and settings. The updated installed app is open at /Users/Shared/MacBridge.app.
- Real remote pairing/deployment and lock/sleep/pinned-tab/Focus actions remain incomplete. No change to those claims.

## Update: polished local preview (0.6.0)
Four native pages, automatic real state reading, playback/app/Shortcut controls, confirmations, activity history and clearer connection setup are installed in `/Users/Shared/MacBridge.app`. The dashboard has responsive light/dark styling and better sign-in/submit states. See `RELEASE_0_6.md` for exact verification and remaining blockers; remote deployment and four OS-dependent actions are still incomplete.
