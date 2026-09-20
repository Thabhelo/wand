# Wand deployment status — 2026-09-20

## Live
- getwand.app: public website on Cloudflare.
- app.getwand.app: new responsive dashboard with pairing, device selection/status, media/volume, app/URL/Shortcut controls, confirmations, command polling, rename/disconnect and data deletion.
- api.getwand.app: Cloudflare Worker, D1 registry, per-device SQLite Durable Objects with hibernating WebSockets. Website proxy is connected. Health check verified.

## Activation blocker
Auth0 public settings are blank. Authenticated endpoints fail closed. The dashboard cannot sign a real user in until an owner-controlled Auth0 SPA/API is configured. No Fly account is needed. See cloud/README.md for configuration. No paid hosting plan was selected.

## Verification
17 Cloudflare runtime tests pass: pairing, ownership, JWT signature/issuer/audience/client/scope/expiry, command lifecycle, injection rejection, reconnect fencing, hibernation recovery, heartbeat expiry, token revocation, account deletion and locked-state privacy. Dashboard tests cover confirmations/cancellation, absent config, pairing review, polling, failures and offline controls. Python reference suite: 40 tests run, 5 skipped. Browser fixture checks verified rendered dashboard/status/offline controls; fixtures never control a real Mac.

Mac source adds X-Wand-Device-ID routing header, preserving hello authentication and v1 message fields. App version 0.9.0 is packaged as an ad-hoc local build; no public notarized download.

## Still not a finished MVP
Real Auth0 login and cloud pairing, physical Mac command acceptance, Muse connector authorization/registration, lock/sleep/pinned-tabs/Focus OS work, Apple signing/notarization, real demo and reviewer acceptance remain. No end-to-end Muse-to-Mac success is claimed.
