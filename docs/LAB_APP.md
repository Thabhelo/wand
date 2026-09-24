# MacBridge Lab — local diagnostic app

MacBridge Lab is a separate developer utility, not the shipped Wand app or the hosted reviewer simulator. Its [source](../agent/Sources/MacBridgeLab/main.swift) has no relay connection, pairing flow, local HTTP server or OS action executor. For the current signed Wand release and physical-action evidence, see [build 34](RELEASE_0_13_1.md) and [desktop acceptance](DESKTOP_ACCEPTANCE.md).

## What it checks

- Read-only GUI-session, OS, legacy CGSession-path and Accessibility diagnostics. Session presence is not proof of an unlocked screen; the lab does not request Accessibility or Automation permission.
- Optional recording of workspace sleep, wake and user-switch notifications. Recording starts off, retains at most 500 local entries and does not cause those transitions.
- Command-schema, deadline, deduplication, simulated lock-state and simulated revocation checks. The unlocked execution path returns `live_actions_disabled`; simulation success never establishes a real OS action.
- A separate byte-exact Shortcut allowlist. Adding an entry never runs the Shortcut.
- An explicit Keychain round-trip check that creates, reads and deletes a random test item under `local.macbridge.lab.storage-test`. This check writes to Keychain; it is not part of the read-only diagnostics. Its result reports whether cleanup completed and never prints the token.
- Local report export containing diagnostics and lifecycle events, excluding command parameters, app names, URLs and tokens.

The packaged bundle uses `local.macbridge.lab` preferences. Simulation logs and deduplication data are stored with owner-only permissions under `~/Library/Application Support/MacBridgeLab/`. Logs can include full simulated command parameters. A simulated revocation acknowledgment clears only the lab warning; the lab cannot revoke a production device.

## Build locally

From the repository root, choose a task-owned output directory:

```sh
swift build --package-path agent --product MacBridgeLab --scratch-path /private/tmp/wand-lab-build
python3 scripts/package_lab.py --binary /private/tmp/wand-lab-build/debug/MacBridgeLab --output '/private/tmp/wand-lab-build/MacBridge Lab.app'
```

[The packaging script](../scripts/package_lab.py) defaults to an ad-hoc local signature. This lab artifact is not the notarized public Wand installer. Its optional Developer ID/notary-profile arguments are separate from the production [release workflow](../.github/workflows/mac-release.yml).

No current lab GUI acceptance run is claimed. Use source tests for protocol checks and the production app for real action acceptance. Remove only task-created build artifacts and test data when finished; preserve production credentials, permissions and logs.
