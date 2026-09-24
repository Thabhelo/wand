# Support form

`https://getwand.app/support/` posts to `/api/support` in the `wand-website` Worker. No sign-in is required.

## Deployment

- Keep Email Routing enabled for `getwand.app` and the owner's destination verified in Cloudflare.
- Store the recipient in the Worker's `SUPPORT_RECIPIENT` secret. Never put it in public assets.
- `SUPPORT_EMAIL` sends from `support@getwand.app` to that fixed recipient. Visitor email is Reply-To, never the recipient.
- Run `npm run check --prefix site`, then `npm run deploy --prefix site`.

Sending to an existing verified destination works on the free plan. Do not enable paid sending or add visitor autoresponses.

## Verification

Submit one clearly labeled test through the live form and verify its arrival in the owner's inbox. A successful API response means Cloudflare accepted the message; inbox delivery is checked separately. Failed sends preserve the form and display an error.

Messages are not stored in D1 or application logs. They remain in the support mailbox. The endpoint limits payload size, checks origin and fields, rejects a honeypot, and limits submissions to three per minute per IP per Cloudflare location. This is basic abuse protection, not a guarantee against distributed spam.

### September 24, 2026: live delivery check

A test sent through the live support form at **07:23:42 UTC** was independently found in the owner's Gmail inbox with the **INBOX** label. The sender was **Wand Support <support@getwand.app>**, with subject **Wand support: Connection**. The message contained branded HTML and a plain-text alternative. Gmail's authentication results reported **SPF: pass, DKIM: pass, DMARC: pass**.

This confirms inbox delivery and formatting for that test, beyond the form's provider-acceptance response.
