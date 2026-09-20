# Deployment configuration

Run one relay process on one machine. SQLite and socket ownership require this constraint. Do not scale horizontally until a shared registry and distributed dispatch are implemented.

Create an Auth0 API with RS256 signing, an HTTPS audience, and `macbridge:control` permission. Create an SPA client for the dashboard and configure its exact HTTPS origin as callback, logout URL and allowed web origin. Admit only this dashboard client and the verified connector OAuth client. Set AUTH0_ISSUER (including trailing slash), AUTH0_DOMAIN, AUTH0_AUDIENCE, AUTH0_WEB_CLIENT_ID and AUTH0_ALLOWED_CLIENT_IDS (comma-separated exact IDs). Tokens are checked for signature, issuer, audience, expiry, client and control scope. No API-key fallback is shipped.

Create a Fly application and a `macbridge_data` volume in the same region, update fly.toml's application name, set the environment configuration, then deploy with `fly deploy --ha=false`. Confirm exactly one machine is running. Provisioning and deployment incur provider charges and have not been performed by this repository.

For Render, deploy the Dockerfile as one always-on web service with a persistent disk mounted at /data and the same environment settings. Verify WebSocket idle handling and HTTPS externally.

Production TLS terminates at the hosting provider. Verify TLS >=1.2 before release. The agent must use HTTPS/WSS; localhost HTTP is for integration tests only. Run Uvicorn without access logs so OAuth callback query strings cannot enter request logs. Do not enable body logging at proxies.

Back up the database only with an explicit deletion/recovery policy. Account deletion in this build removes active application records, not hosted Auth0 identities or external backups. Neither automatic backup restore deletion replay nor hosted identity deletion is implemented.

## Guided connection release (0.7)

Package the app with `--relay-origin https://YOUR_DEPLOYED_ORIGIN`. This embeds the HTTPS service address in the signed bundle; customers need no relay settings. Do not ship a public customer build without configuring and validating this service. The default development build intentionally has no guessed domain.

The app opens `/#pair=ABC234` and can render that link as a QR code. This contains only the short-lived pairing code, never the bootstrap or device credential. The dashboard strips the fragment, retains the code in tab-scoped session storage for at most ten minutes across hosted sign-in, displays the authenticated account and server-resolved device name, and requires explicit approval. Preview does not claim. The fragment is not sent in HTTP requests; dashboard referrer policy is no-referrer. Anyone who obtains the code could attempt pairing, so do not share screenshots of active codes publicly.

Deploy relay and agent together: the relay now sends a schema-validated `ready` event after token validation and socket registration. The agent requires the matching device ID before showing Mac connected and times out missing readiness after ten seconds. This proves authenticated transport, not a successful physical action or Muse authorization.

Pairing cancellation calls a bootstrap-authenticated endpoint which revokes even a credential redeemed during cancellation. Network failure leaves the persistent dashboard revocation warning instead of claiming cancellation completed.

Muse account authorization remains separate and unimplemented until the actual connector integration contract and approved directory entry are available. No invented Muse authorization URL, callback or automatic account federation is used.
