# Phase 1 — protocol slice, 2026-09-20

The user approved Phase 0 with eight amendments; no further baseline approval is pending. The amended contract is in CONTRACT_REVIEW.md. Phase 1 has started. This is **not a complete Mac agent** and is not deployed. A native menu-bar diagnostic/simulation app is now packaged; see [Lab app status](LAB_APP.md) for current build details and UI verification limitations.

## Implemented and exercised

- Python fake device first, then a Python fake relay test peer using actual loopback WebSockets; neither is the production relay.
- Swift 6 protocol probe with URLSessionWebSocketTask, 64 KiB receive bound, shared JSON Schema validation, hello, heartbeat, delivered/result, revoke/4003 and revoke_self handling.
- Python and Swift consume the same canonical schema and 58 shared positive/negative fixtures. The Swift validator supports only the schema vocabulary used here and rejects unknown keywords; it is not a general JSON Schema library.
- Expiry rejection at more than 5 seconds stale, including pre-execution recheck; reject deadlines more than 20 seconds ahead. Durable command-ID reservation before handling; 10,000-entry/10-minute ledger and corruption fail-closed behavior.
- Locked-state gate: get_state discloses only screen_locked; lock_screen acknowledges already_locked; all other actions fail device_locked, unknown state fails closed.
- Local full-parameter forensic log, owner-only directory/files, 90-day pruning on writes and 10 MiB oldest-first cap. No state payloads or tokens in entries. Production still needs periodic pruning while idle, clear/export UI, and disk-full handling surfaced to the user.
- Persistent revocation-pending state and HTTPS dashboard-link builder. Socket self-revoke is sent before disconnect, credentials cleared locally, timeout remains pending; revoke or 4003 acknowledges completion. A simulated blocking menu-bar/window UI is now built in MacBridge Lab; production pairing/revocation UI is still pending.
- Pairing cadence policy (3 seconds ±0.5s, stop on expiry/view close) is tested; no actual pairing HTTP client yet.

The probe always simulates a locked Mac. It never calls AppKit actions, AppleScript, Process or Keychain. An ephemeral test token arrives on stdin and never reaches disk. This exception exists only in a clearly separate loopback test executable; production credentials will use Keychain. The protocol probe deliberately refuses non-loopback and non-test URLs.

## Reproduce

```sh
cd macbridge
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
make verify
make spike
```

`make verify` builds with swiftc, runs eight standalone Swift policy checks, validates 58 shared fixtures in Swift, then runs Python contract and WebSocket integration tests including the compiled Swift peer. `make test` alone skips Swift integration unless MACBRIDGE_SWIFT_PROBE is supplied; use verify for full coverage.

Toolchain blocker resolved after the user installed and opened Xcode 27.0 (27A266a). xcode-select now points to /Applications/Xcode.app/Contents/Developer. A normal SwiftPM build succeeded, and its binaries passed all 8 policy checks, 58 shared fixtures and 27 Python contract/integration tests. The earlier Command Line Tools installation failed manifest linking; the direct compiler fallback remains available through make verify. Normal builds still need permission to write the compiler module cache when run inside the restricted Codex sandbox. No system toolchain files were edited by the agent.

## Empirical discovery on this Mac

The read-only 20-line discovery spike ran on macOS 26.6.2:

| Check | Observed | Interpretation |
| --- | --- | --- |
| Specified CGSession path | Missing | Cannot wire the prompt's proposed path without an alternative verified API. |
| Installed Safari tab dictionary | No declared pinned property | Does not establish a safe pinned-tab-preserving action. |
| Installed Chrome tab dictionary | No declared pinned property | Requires a separate safe API/behavior spike. |
| Sleep/wake | Not exercised | Must verify clean offline state, fresh connection generation, no stale execution on wake. |

These are static discovery results, not proof that locking or pinned-tab detection is impossible. No real lock, sleep, quit, tab close or permission prompt was performed. macOS 27 has not been exercised.

## Remaining Phase 1 work

1. Verify safe locking, lock detection, pinned-tab detection, DND, media automation, graceful quit, Shortcut argv/allowlist behavior, and sleep/wake on macOS 26 and 27. Unknown support must fail closed, not silently use synthetic keystrokes or private preference edits.
2. Production client with Keychain storage, polling HTTP pairing, reconnect/backoff, NSWorkspace sleep/wake lifecycle and generation fencing. The current probe is single-session, deliberately not a background reconnecting app.
3. Promote the new LSUIElement Lab UI and Shortcut editor into a production agent: real pairing/revocation, dashboard deep link, local log clear/export, and permission explanations. Local .app packaging exists; notarization remains unrun.
4. Local 127.0.0.1 API with a separate Keychain bearer and the same execution/validation guards.
5. Signing/notarization script and deliberate real-device acceptance session.

The protocol prerequisite is demonstrated. Do not start production relay implementation until remaining agent work can exercise meaningful actions against the stub, per the original phase order. Account deletion cascade, failed-hello IP limiter and OAuth per-client scopes are specified contracts for Phase 2, not claims of running server code. Out-of-band high-risk step-up approval is explicitly a v2 requirement.

## Xcode verification commands

```sh
swift build --package-path agent --scratch-path /private/tmp/macbridge-xcode-build --cache-path /private/tmp/macbridge-xcode-cache --config-path /private/tmp/macbridge-swift-config --security-path /private/tmp/macbridge-swift-security
/private/tmp/macbridge-xcode-build/debug/PolicyChecks
/private/tmp/macbridge-xcode-build/debug/ProtocolProbe --schema contracts/v1.schema.json --validate-fixtures contracts/fixtures.json
MACBRIDGE_SWIFT_PROBE=/private/tmp/macbridge-xcode-build/debug/ProtocolProbe .venv/bin/python -m unittest discover -s tests -v
```
