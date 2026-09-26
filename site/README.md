# Wand website

Cloudflare serves the public site at `getwand.app` and the account dashboard at `app.getwand.app`. `www.getwand.app` is also routed through this Worker. Google sign-in is configured through Firebase. Account API requests are proxied to the relay at `https://api.getwand.app`; the Mac connects to that relay directly over HTTPS and outbound WebSockets.

## Develop and deploy

Run these commands from `site/`:

```sh
npm ci
npm run dev
```

`npm run check` runs the website, dashboard, routing and feedback tests. `npm run deploy` publishes the Worker and static assets using the authorized Cloudflare account. Both development and deployment first synchronize the shared dashboard assets from `../web`; edit those source files rather than their generated copies in `public/`.

`wrangler.jsonc` defines the production domains, `RELAY_ORIGIN`, support-email binding and support rate limit. Without a relay origin, account API requests fail closed with 503. Request observability stays disabled to avoid recording authorization callback parameters. The support form setup is documented in [SUPPORT_FORM.md](../docs/SUPPORT_FORM.md).

## Publish a blog post

1. Add the title, description, date, author and URL slug to `content/blog/posts.json`.
2. Write `content/blog/<slug>.html` as an article fragment. Use `<h2 id="section-name">` for sections; the table of contents is generated. This is trusted, reviewed author content, not user-submitted HTML.
3. Add a 1200 × 630 PNG share image under `public/blog-assets/` and reference it in the post metadata.
4. Run `npm run build:blog`, then `npm run check`. Preview with `npm run dev`, review on a phone-sized screen, and deploy normally.

The build creates the blog index, article pages, RSS feed and sitemap entries. Commit generated pages with their source. Both `dev` and `deploy` rebuild them automatically. No database or paid service is needed. Keep historical posts dated; correct factual errors in the source and rebuild. Removing a published post also requires removing its generated article directory and deciding where existing links should redirect.

## Downloads and connection status

The download page serves signed, notarized Wand installers from `public/releases/`, with a SHA-256 manifest. Use the [release workflow](../docs/AUTOMATED_RELEASES.md) to prepare a new installer and verify it before publication. Do not publish an arbitrary local development build.

Muse can use the web controls today. Its native connector application has been submitted; client registration and native connection testing remain pending. Keep public copy consistent with [BUILD_STATUS.md](../docs/BUILD_STATUS.md).
