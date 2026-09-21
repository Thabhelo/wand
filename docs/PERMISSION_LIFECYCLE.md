# Permission lifecycle release gate

Goal: normal launches and same-identity updates reuse granted permissions without asking for passwords. Apple can still require consent after OS changes or permission resets; this gate does not promise otherwise.

## Implementation

- One `credentials` item under `local.macbridge.agent.credentials-v2` stores Wand's credential dictionary in Keychain. No credentials move to preferences, files, URLs, or logs.
- Existing credentials are copied only after authorized reads; the saved dictionary is read back and compared before migration completes. Legacy records remain untouched during migration, preserving rollback. Once a vault exists, missing entries do not fall back to legacy records.
- Access uses the new item's default app-owned Keychain access list. No all-applications access is granted.
- Background startup forbids authentication UI. An explicit Connect retries authorized access; this is recovery, not a substitute for passing silent startup.
- Desktop consent stays in the existing preferences; no TCC reset or permission entry deletion is part of installation.
- `package_agent.py --upgrade-from /Users/Shared/Wand.app` verifies both signatures and rejects a changed designated requirement before publishing the candidate bundle. Existing output bundles are checked automatically.
- Development-key signing authorization is separate from end-user app permissions and must not be part of customer installation.

## Required physical checks

Record version, build, signing requirement, and observed results without tokens or screenshots of credentials.

1. Fresh user installs signed app, completes guided Accessibility and Screen Recording setup, and pairs.
2. Capture a disposable app and perform a harmless action through the relay.
3. Quit and relaunch unchanged app; it reconnects without Connect or Keychain approval.
4. Install a newer build with the same identity, relaunch, and repeat capture/input without permission changes.
5. Restart the Mac, unlock normally, relaunch and repeat. OS login itself is not a Wand permission prompt.
6. Confirm Pause and account/device revocation continue to work; stored permissions must not override a user's decision to stop control.

Do not mark this gate passed from unit tests, noninteractive error suppression, or successful local actions alone.

## Current evidence

Build 21 failed check 3: after the owner approved existing credential access and Wand connected, an unchanged-app relaunch reported connection keys locked. Desktop consent persisted. This was the failure that prompted the consolidated storage fix.

## September 21 verified results

- Build 22 migration completed after explicit owner approval; credentials remained in Keychain.
- Quit/relaunch of unchanged build 22 reconnected silently without clicking Connect or granting Keychain access. Desktop consent persisted.
- Production relay desktop_observe returned a real Safari about:blank screenshot after the silent restart.
- Build 23 includes a real binary change: silently retry unopened credential access after wake/session activation. Packaged with --upgrade-from; designated requirement remained unchanged.
- Installed build 23 over build 22. It connected automatically and remote screenshot capture passed without new Keychain, Accessibility, or Screen Recording approval.
- A remote press test was rejected by the existing active-window guard; no input success is claimed for that attempt.
- Three real codesign guard tests pass (same requirement, changed requirement, unsigned candidate); 14 Swift tests passed on the storage change.

This demonstrates app restart and signed-update persistence on the owner's existing installation. After a full Mac reboot, Wand was opened manually and the owner confirmed it connected without a password prompt. Automatic launch at login, fresh-user setup, and post-reboot desktop capture/input remain unverified. Build 23 is published at https://getwand.app/download/. The downloaded public DMG matches the verified package. Cloudflare deployment: 8435171f-0813-4e7f-aeb9-7148c2eea2c2.
