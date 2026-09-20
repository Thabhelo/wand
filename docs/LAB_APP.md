# MacBridge Lab — local test build

This is a Phase 1 diagnostic/simulation app, not the remote-control MVP. Live actions are disabled in code. There is no relay connection, pairing HTTP flow, local HTTP server, or real OS action executor in this build.

## Open

Source-tree build output: `dist/MacBridge Lab.app`. Use the verified temporary copy below: Finder/iCloud added disallowed signing metadata to the copy under Documents after packaging.

For the Standard test account, a copy is staged at:

`/private/tmp/macbridge-test-session-20260920/MacBridge Lab.app`

Use Finder → Go → Go to Folder to open the directory. The temporary copy may disappear after system cleanup; recreate it from the build output when needed. No Codex chat history, auth files, API keys or production device tokens are copied into this folder.

No account switch is needed to inspect the app or run simulations. Do not run real sleep/wake tests while work in the main session could be interrupted.

## Available checks

- Read-only GUI-session availability, OS version, legacy CGSession-path presence, and Accessibility status. The app does not request Accessibility or Automation permissions. Active session is never treated as proof of an unlocked screen.
- Session-event recording: captures NSWorkspace sleep, wake and user-switch event labels plus timestamps/generation numbers. It does not cause those transitions. Events are local, bounded to 500 entries, and recording is off on launch.
- Command simulation: canonical schema validation, deadline checks, durable dedup reservation, a simulated lock gate, full-parameter local log, and pending-revocation blocking. All output is explicitly marked simulation. The app cannot execute actual Mac actions.
- Shortcut allowlist editor: byte-exact names, no whitespace/case/Unicode normalization. This test app's list is separate from any future production list.
- User-initiated Keychain check: generates a random test item, writes and reads it using Generic Password Keychain services, then deletes it and verifies deletion. No token enters a file, log, process argument or URL. The check has not yet been run through the GUI.
- Safe report export: OS/session diagnostics and lifecycle events only. Excludes command parameters, running-app lists, URLs and tokens.

Preferences live under `local.macbridge.lab`. Simulation logs and dedup data live under the current user's `~/Library/Application Support/MacBridgeLab/` with owner-only file/directory permissions. No device pairing exists, so the simulated server acknowledgment clears only the test warning and never claims real server-side revocation.

## Suggested initial walkthrough

1. Refresh read-only checks; lock detection must remain unverified and live actions disabled.
2. Leave "Simulate a locked Mac" on. Run get_state with `{}`; expect only screen_locked=true. Run lock_screen with `{}`; expect already_locked=true. No actual lock occurs.
3. Simulate offline revoke; command controls must disable and remain disabled after restarting the app. Simulate server acknowledgment to clear only the simulated pending state.
4. Add `MacBridge Test Notification` to the allowlist. Turn simulated locked state off and select run_shortcut. An unknown name must return action_not_allowlisted. The known name must return live_actions_disabled, never pretend it ran.
5. Test Keychain storage when ready; the pass message must confirm cleanup.
6. In the dedicated test session, record lifecycle changes during a deliberately scheduled user-switch/sleep/wake run. That real-device run is still pending.

## Build and packaging

```sh
swift test --package-path agent --scratch-path /private/tmp/macbridge-xcode-build --cache-path /private/tmp/macbridge-xcode-cache --config-path /private/tmp/macbridge-swift-config --security-path /private/tmp/macbridge-swift-security
python3 scripts/package_lab.py --binary /private/tmp/macbridge-xcode-build/debug/MacBridgeLab --output '/private/tmp/macbridge-test-session-20260920/MacBridge Lab.app'
```

The default package is ad-hoc signed for local development and is **not notarized**. Distribution requires an appropriate Developer ID identity and an existing Keychain notary profile:

```sh
python3 scripts/package_lab.py --binary /path/to/release/MacBridgeLab --identity 'Developer ID Application: YOUR IDENTITY' --dmg --notary-profile YOUR_KEYCHAIN_PROFILE
```

Those distribution steps have not been run. Never pass Apple passwords in command arguments or disable Gatekeeper to install this build.

## Verification and limits

Four native XCTest cases pass: session-generation invalidation, exact allowlist matching including Unicode edge cases, token generation, and fail-closed/data-minimized diagnostics. The bundle Info.plist and the temporary copy’s ad-hoc signature verify. Packaging removes only FinderInfo and ResourceFork metadata from its own generated bundle before signing; it does not strip quarantine or weaken Gatekeeper. UI visual verification and the Keychain GUI round trip are pending: the computer-use service crashed when trying to select this custom app. The inspected crash report names SkyComputerUseService (SIGTRAP), not MacBridgeLab; a separate process check confirms MacBridgeLab is running, but the rendered interface remains unverified.

API investigation still blocks real lock-state enforcement, modern locking, pinned-tab preservation and DND. Installed scripting dictionaries expose no pinned property. Apple's CGSession header exposes session identity/console/login fields, not a documented locked-state property. Do not infer support from session presence or trigger private APIs/keystrokes as a silent fallback.

Sources consulted: [Apple session dictionary API](https://developer.apple.com/documentation/coregraphics/cgsessioncopycurrentdictionary()), [Apple user-session notification](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidresignactivenotification), [Keychain accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility), [Chromium AppleScript support](https://www.chromium.org/developers/design-documents/applescript/). Local SDK headers and installed app dictionaries were also inspected.
