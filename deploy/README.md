# Deployment

Start with the [project README](../README.md) and [current build status](../docs/BUILD_STATUS.md).

| Service | Production setup | Runbook |
|---|---|---|
| `getwand.app`, `app.getwand.app` | Cloudflare Worker and static assets | [Website](../site/README.md) |
| `api.getwand.app` | Cloudflare Worker, D1 registry, per-device SQLite Durable Objects and OAuth KV | [Relay](../cloud/README.md) |
| User sign-in | Firebase Authentication, project `wand-getwand`; Google sign-in | [Authentication](../docs/FIREBASE_CONNECTIONS.md) |
| Mac installer | Developer ID signing and Apple notarization through GitHub Actions | [Releases](../docs/AUTOMATED_RELEASES.md) |

Deploy the relay from `cloud/` and the website from `site/`. Their `wrangler.jsonc` files define the production domains and bindings. Review database migrations before relay deployment, run each component's checks, and verify the public routes afterward. Registry maintenance uses a [Durable Object alarm](../docs/REGISTRY_CLEANUP.md), so it does not require another Cron Trigger.

Customer builds embed `https://api.getwand.app` and `https://app.getwand.app`. The Mac opens the authenticated pairing flow in the browser and keeps its device credentials in Keychain. Muse's native connector authorization is a separate OAuth consent flow; see [build status](../docs/BUILD_STATUS.md) for registration and review progress.

`Dockerfile`, `fly.toml` and `wand.env.example` belong to the earlier Python/Auth0 reference relay. They are not used by the deployed Cloudflare service. Do not use their single-process SQLite constraints or Auth0 variables to configure production.

Keep credentials out of repository files and request logs. Restore provider backups only with a plan to replay account/device deletions before service resumes.
