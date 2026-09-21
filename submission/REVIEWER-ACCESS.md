# Wand reviewer access — September 20, 2026

Open https://app.getwand.app/review/ in a desktop browser and sign in with Google. No shared password or developer account is needed. Click Create test Mac. This creates a device belonging only to your account and authenticates its outbound socket to the production relay. The device credential is generated in browser memory, never put in a URL or local storage.

1. Send Check Mac status; wait for succeeded and synthetic state.
2. Send Mute the Mac; expect succeeded, with no physical effect.
3. Try an unapproved Shortcut; confirm the simulated action and expect action_not_allowlisted. Review Demo is the only approved synthetic shortcut.
4. Take offline; send a command and expect device_offline with last_seen. Reconnect to resume.
5. Lock the simulated Mac; check state and observe only screen_locked:true. Repeated lock succeeds with already_locked:true. Other actions fail device_locked.
6. Revoke test Mac to invalidate its credential. Create a new device to restart.

Closing the page drops the socket. Revoke any leftover test device from https://app.getwand.app/. Test records follow the documented retention policy; deleting your Wand account removes its records.

## What this demonstrates
Real hosted Google authentication, code issuance/claim/redemption, ownership checks, WebSocket command dispatch/results, offline rejection, and revocation. Actions execute in a browser simulator, not in macOS. It is not a Muse OAuth end-to-end test. Muse's client and callback are not registered yet; reviewers should provide verified registration details. Whether Meta accepts this sandbox as sufficient is not established.

Native beta: https://getwand.app/download (Apple silicon, macOS 26+, unnotarized). Instructions explain the per-app macOS Open Anyway exception. Physical remote pairing and OS-dependent actions still require acceptance testing. Do not describe simulated lock/sleep/browser behavior as implemented native behavior.

Verified live in Chrome: signed-in pairing, get_state succeeded, offline rejection with last_seen, reconnection and device revocation. No personal Mac was exposed to reviewers.
