# Wand hosted relay

Cloudflare Workers at https://api.getwand.app, D1 wand-registry and one SQLite Durable Object per device. These services have free tiers with quotas; this is not unlimited free hosting. No paid plan was selected.

Use Node 22/24 LTS. Run npm ci, npm run build:contracts, npm test. Validators compile from ../contracts/v1.schema.json before deployment, without runtime eval. Tests use isolated Workers bindings and no production auth bypass.

## Sign-in configuration
Create an Auth0 Single Page Application and API: identifier https://api.getwand.app, RS256 and macbridge:control scope. Callback/logout/web origin: https://app.getwand.app. Set AUTH0_DOMAIN, AUTH0_ISSUER (with trailing slash), AUTH0_WEB_CLIENT_ID and AUTH0_ALLOWED_CLIENT_IDS in wrangler.jsonc. These are public settings. Never admit an unverified connector client.

## Deploy
Run npm exec wrangler -- d1 migrations apply wand-registry --remote, then npm run deploy. The website proxies account API calls to this relay. Observability is off; explicit logs contain only action, outcome and latency.

See ../contracts/TRANSPORT.md for the device routing header. No offline queue or reconnect replay. Ownership and heartbeat freshness are checked before dispatch. Cloud command/audit records contain no raw params or state. Alarms purge commands/audits after 90 days; hourly cleanup expires pairing records. Account deletion revokes all tokens before socket closure and active-record purge. Provider recovery backups/Time Travel are not erased by row deletion; restoration needs deletion replay before service resumes.

Auth0 is not configured yet. Tests with fake devices do not prove physical Mac actions or Muse integration. Verify real sign-in, Mac pairing and connector authorization before declaring the product complete.
