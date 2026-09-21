# Wand 0.9.3 beta

- Public unnotarized DMG at https://getwand.app/releases/Wand-0.9.3.dmg; no Apple membership purchase. /download explains installation, per-app Open Anyway, Keychain approval and incomplete features.
- Installed /Users/Shared/Wand.app; previous app retained as Wand-previous-0.9.2.app. Added guarded asynchronous Keychain retry directly to Connection button. Startup remains responsive. User must approve the OS dialog; no credentials removed or bypassed.
- Hosted reviewer sandbox at https://app.getwand.app/review/ uses actual Firebase account sign-in and production pairing/relay, with only the device execution simulated. No public auth bypass, shared test password, or token in URLs. Public device ID routes the socket; hello still requires the 256-bit credential. Browser credential lives only in memory. Origin restricted to dashboard for this socket proxy.
- Live Chrome checks: pair, succeeded get_state, offline rejection with last_seen, reconnect, revoke. Downloaded DMG SHA-256 matches packaged artifact. Seven routing tests passed; native release build and strict ad-hoc signature verification passed.
- Muse submission is still a draft, not sent. No registered Muse callback or real phone-to-Mac acceptance. This beta does not implement native lock, sleep, pinned-tab cleanup or Focus.
