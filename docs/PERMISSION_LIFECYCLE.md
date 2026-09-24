# Permission lifecycle

Normal launches and updates signed with the same identity should reuse granted access. macOS can still require consent after an identity change, OS change or permission reset. Wand does not promise permanent approval under every condition.

## Implementation

- One `credentials` item under `local.macbridge.agent.credentials-v2` holds connection credentials in Keychain. Connection setup reads the vault once. Credentials do not move to preferences, files, URLs or logs.
- Older separate items are migrated only after all authorized reads finish. Connection setup saves the vault only when values change; legacy records remain for rollback. Once a vault exists, missing entries do not fall back to those records.
- The vault uses the app's Keychain access list, without granting access to every application. Background startup suppresses authentication UI; an explicit Connect can request access when recovery is needed.
- Desktop-control consent persists in preferences. Installers do not reset Accessibility, Screen Recording or Keychain permissions.
- `scripts/package_agent.py --upgrade-from /path/to/installed/Wand.app` verifies both signatures and refuses a changed designated requirement. Existing output bundles are checked automatically. Keep the current installed path when updating.
- Developer signing-key authorization is separate from customer app permissions. CI uses an isolated signing Keychain; users do not approve the developer's private key.

## September 24: same-team build 34

Wand **0.13.1 (34)** is signed by Thabhelo Duve, team `58XWD3LBSS`, with bundle identifier `local.macbridge.agent`. The final artifact came from source `0d7960f` and [CI run 35975546500](https://github.com/Thabhelo/wand/actions/runs/35975546500). App/DMG signatures, stapled notarization tickets and Gatekeeper passed. The public download matched the verified DMG hash recorded in [the release notes](RELEASE_0_13_1.md).

Verified on the owner's Mac:

- Updating the existing `~/Applications/Wand.app` from the same signing team reconnected without another Keychain or privacy prompt.
- The final artifact's first Safari and TextEdit screenshots succeeded without manually raising their windows. Text entered through the relay was independently confirmed in TextEdit.
- After confirmed process exit and relaunch, Wand reconnected without another prompt. Its first Safari image request after restart returned Example Domain and a complete image.
- A physical sleep test recorded about 43 seconds asleep, followed by the owner's manual wake and successful reconnect. The native volume display matched the Mac without changing it. Disposable test files were removed.

Earlier build 34 candidate tests verified lock/repeated-lock results and Safari pinned-tab cleanup. See [desktop acceptance](DESKTOP_ACCEPTANCE.md#september-24-build-34-release-results) for the distinction between candidate tests and final-artifact tests.

Fresh-user or second-Mac installation, a full Mac reboot under this identity, and the live 75-second missed-heartbeat/offline interval remain open. The owner woke the Mac before the longer interval could be measured. Existing-installation success does not establish those checks.

## September 24: owner signing, build 33

Build 33 deliberately replaced build 32's signing team with `58XWD3LBSS`. This migration exposed stale Keychain trusted-app references and macOS privacy records tied to older development identities. The owner approved the installed app's Keychain access and targeted repairs to Wand's Accessibility and Screen Recording entries. No blanket permission reset or all-applications Keychain grant was used.

Those repairs restored real capture/input and unchanged-app restart persistence. They were a repair for that signing migration, not a step for every installation or update. Superseded build-by-build investigations remain in Git history.

## Release checks and regression diagnosis

For each release, record the build, signing requirement and results without credentials or screenshots of password dialogs:

1. On a fresh user or second Mac, install, pair and complete the guided privacy approvals.
2. Observe a disposable app and perform a harmless action through the production relay.
3. Quit and reopen the unchanged app; verify automatic reconnect and capture/input without renewed approval.
4. Install a newer build with the same identity and repeat.
5. Restart the Mac, unlock normally, and verify startup/reconnect and capture/input. OS login is separate from Wand permission approval.
6. Verify Pause and device/account revocation still stop access. Persistent grants must not override revocation.

If access regresses, first confirm the running app's path, signature and designated requirement. Capture the failing stage and OSStatus before requesting another approval or reset. A connection-key message can also cover local-server initialization failure. A Settings toggle alone does not prove that the running process is trusted.

Unit tests, suppressed dialogs and local-only actions do not replace these physical checks. Close test windows and remove disposable files afterward.
