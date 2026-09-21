# Wand deployment status — 2026-09-20

## Live and verified
- getwand.app: public website on Cloudflare.
- app.getwand.app: Firebase Google sign-in completed in Chrome as thabheloduve@gmail.com; the signed-in dashboard loaded the protected device list from the deployed relay.
- api.getwand.app: Cloudflare Worker, D1 registry, per-device SQLite Durable Objects with hibernating WebSockets. Firebase project `wand-getwand` is on the no-cost Spark plan.
- Separate OAuth authorization and token endpoints, discovery metadata, device/action consent, connector revocation and account-deletion cascade are deployed. MUSE_CLIENT_IDS is intentionally empty until verified client registration; arbitrary clients cannot claim to be Muse.

## Verification
29 Cloudflare runtime tests pass, including real OAuth code/token exchange in isolated bindings, replay/PKCE rejection, narrowed refresh scopes, per-device/action authorization, separate dashboard/connector token acceptance, revocation and account deletion. Dashboard checks and six website routing tests pass. These tests use a fake OAuth client and device peer, not the real Muse service.

The live Google sign-in was verified without an auth bypass, test password, service-account impersonation or copying user tokens into the command line. Website and native pairing share the dashboard's Firebase identity. The native app retains only its own device token in Keychain.

## Remaining release work
- Register the genuine Muse connector using verified client/callback details, then test iPhone → Muse → Wand → Mac. No real Muse-to-Mac success is claimed.
- Verify native cloud pairing and physical Mac acceptance against this identity.
- Complete lock/sleep/pinned-tabs/Focus OS work.
- Apple Developer signing/notarization: signing inventory previously showed zero valid identities. Current 0.9.1 Mac build is ad-hoc signed.
- Complete release legal/support details, demo and reviewer acceptance.

No Auth0 or Fly account is required. No paid plan was selected. Google and Cloudflare free tiers have quotas.
