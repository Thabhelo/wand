# Wand hosted relay

Cloudflare Workers at https://api.getwand.app, D1 `wand-registry` and one SQLite Durable Object per device. Firebase Authentication project `wand-getwand` provides user sign-in. The deployment uses the providers' free tiers, which have quotas. See [current build status](../docs/BUILD_STATUS.md) for release and integration progress.

Use Node 22/24 LTS. Run `npm ci`, `npm run build:contracts`, `npm test`. Validators compile from `../contracts/v1.schema.json` before deployment. Tests use isolated Workers bindings, never a production auth bypass.

## Two separate permissions

The dashboard uses Firebase Google sign-in, with Facebook hidden from public sign-in while Meta verification is deferred. Its ID tokens must have the project-specific issuer/audience, an approved Google/Facebook sign-in provider, valid signature and timestamps; Google also requires a verified email claim. Facebook identity is the Firebase UID, never an email-based ownership lookup. The app connects a device to this same account through the existing browser pairing ceremony; it never stores the Google token. Only device credentials are stored in Keychain.

The assistant uses Wand's separate OAuth authorization server, built with `@cloudflare/workers-oauth-provider`. Firebase ID tokens are not accepted at `/connector/*`; connector tokens are not accepted at dashboard administration endpoints. `/authorize` requires a registered client on `MUSE_CLIENT_IDS`, an exact registered callback, S256 PKCE, state, resource `https://api.getwand.app/connector`, and action scopes `wand:<catalog_action>`. No public dynamic client registration or client-metadata URL fetching is enabled.

Consent requires an authenticated user, explicitly chosen devices/actions and an Allow click. High-risk actions are unchecked initially. Consent requests expire after ten minutes, bind to the first authenticated reviewer and are single-use. Tokens last 15 minutes, refresh grants 30 days. Each command checks the D1 connection record, permitted device, permitted action and current ownership. Narrowed token scopes cannot widen the original grant. Revoking a connection blocks issued tokens immediately through D1 and purges available OAuth grants from KV. Account deletion installs a deletion barrier, revokes OAuth grants, deletes connection records, revokes all device tokens, closes sockets and purges device data.

Firebase user-session revocation is subject to Firebase ID-token expiry (up to one hour); this verifier does not contact Firebase Admin on every request. Account/device/connector revocation in Wand is checked on the relay. KV propagation can delay physical OAuth-record deletion; D1 revocation remains authoritative. An action already dispatched cannot be recalled.

## Deployment

`npm exec wrangler -- d1 migrations apply wand-registry --remote`, then `npm run deploy`. Set public `FIREBASE_*` web configuration in wrangler.jsonc. Firebase authorized domains include app.getwand.app and getwand.app. The website proxies account API calls to this relay. Website deployment copies canonical dashboard files from `../web`.

Wand's separate connector OAuth service is implemented and tested with a fake client. The Muse application has been submitted; verified native client/callback registration and a native connection test remain pending. `MUSE_CLIENT_IDS` is empty in the checked-in configuration until that registration is complete. Muse has used Wand through the web controls; that does not establish a native connector connection. Public discovery: https://api.getwand.app/openapi.json and https://api.getwand.app/.well-known/oauth-authorization-server.

See [the transport contract](../contracts/TRANSPORT.md) for device routing. No offline queue or reconnect replay. Cloud command/audit records contain no raw params or state. Device alarms purge commands/audits after 90 days; the [registry alarm](../docs/REGISTRY_CLEANUP.md) expires pairing and consent records hourly. Restoring provider backups needs deletion replay before service resumes. The signed, notarized Mac release is available from [the download page](https://getwand.app/download/); [release evidence](../docs/RELEASE_0_13_1.md) records what was tested and what remains open.

## Facebook activation
The browser adapter supports Facebook sign-in and explicit linking from an existing signed-in account. Configure a dedicated Meta Facebook Login app, register `https://wand-getwand.firebaseapp.com/__/auth/handler` as its exact redirect, and save its app ID/secret in Firebase Authentication (not in this repository). After verification, set FACEBOOK_ENABLED to true and deploy. No email-based account merging occurs in Wand. Facebook linking and sign-in were verified for the developer account on 2026-09-20. FACEBOOK_ENABLED is now false to keep public onboarding Google-only. The Firebase provider is retained for existing linked accounts; Meta verification is not on the release critical path.
