# Wand website

Run `npm ci` then `npm run dev` in this directory. `npm run check` checks host routing and the unavailable-service boundary. `npm run deploy` publishes the Worker and its static assets once Wrangler is authorized for the domain-owning Cloudflare account.

Domains: getwand.app and www.getwand.app serve the public site; app.getwand.app serves the account dashboard. The Mac app connects directly to api.getwand.app over HTTPS and outbound WebSockets. The dashboard proxies its API requests through this Worker to the same relay. Dashboard HTML is synchronized from ../web/index.html before development and deployment.

RELAY_ORIGIN points to the deployed Cloudflare relay at https://api.getwand.app. Sign-in is still disabled until its hosted authentication configuration is supplied. Without a relay origin, account API requests fail closed with 503. No credentials belong in this file. Request observability is disabled to avoid recording authorization callback parameters.

The download page deliberately has no public installer until Developer ID signing and Apple notarization pass. The local dist/Wand.dmg is an ad-hoc signed developer build, not a public release.
