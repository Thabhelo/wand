# MacBridge 0.6 preview — 2026-09-20

## Installed changes

The AppKit application now has four dedicated pages: This Mac, Shortcuts, Activity and Connection. Native controls, system typography, a translucent sidebar, adaptive light/dark colors, rounded cards and a persistent action result replace the long test form. State is read automatically on startup through the real guarded command path.

Local UI exposes playback, volume/mute, opening an installed app, graceful app quitting, opening HTTP(S) websites, and adding/removing/running exact allowlisted Shortcuts. Quit and Shortcut execution require a confirmation naming the target. Errors explain the next action. Recent activity shows up to 20 terminal outcomes and timestamps; full parameters remain in the private local log, and state payloads are not logged.

Connection setup now exposes pairing, cancellation, the dashboard, revoke confirmation and acknowledgment of offline revocation. No account is required for local commands. The web dashboard has matching responsive light/dark styling, loading/error sign-in states and duplicate pairing-submit protection.

Shortcut execution uses a Process argument array with `run -- name`. The installed Shortcuts CLI accepted a deliberately nonexistent leading-hyphen operand and returned `Couldn't find shortcut`, verifying option termination without running a user Shortcut. Exact byte matching also applies when removing an allowlist entry.

## Verification

- Eight Swift tests pass, including real read-only state collection and local API security.
- Thirty-eight Python tests pass, including shared schema/Swift peer and relay integration tests. The first invocation used the wrong working directory and was corrected; the recorded pass is from the repository directory.
- Dashboard inline JavaScript parses successfully.
- Installed app 0.6 launched; its native accessibility tree and screenshot show real battery/app information and a successful state read.
- Sidebar navigation to Shortcuts and Connection was verified. An intermediate capture failed with ScreenCaptureKit -3811; after reopening the final build, Activity displayed real history, the empty-website error was visible, and Refresh updated real state. Full physical-action GUI coverage is not claimed.
- No real Shortcut, app quit, physical lock/sleep, or browser-tab close was executed during this change.

## Still required before an MVP release

1. Implement and physically validate lock, sleep, pinned-tab-preserving browser cleanup and Focus on supported macOS versions. These remain explicit unsupported actions, not simulated successes.
2. Configure Auth0, domain and hosted relay; test actual pairing, command dispatch, network loss, revocation and account deletion with the installed agent.
3. Verify Muse's actual connector import/OAuth requirements with platform access. Draft manifest/spec are not proof of platform acceptance.
4. Developer ID signing, notarization, externally accessible reviewer sandbox and recorded demo.

This is a useful local preview, not a complete shipped Muse integration.
