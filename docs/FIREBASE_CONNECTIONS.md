# Account sign-in and assistant authorization

Wand uses **Firebase Google sign-in** for account identity (and a password sign-in for one designated reviewer account, described below) and Cloudflare D1 for the device registry. Production does not use Auth0 or Firestore. `getwand.app` and the Mac app both send account setup to `app.getwand.app`; the Mac stores device credentials in Keychain and needs neither a Firebase SDK nor Google tokens.

## Assistant connection

Wand OAuth is separate from Google sign-in: the owner signs in, selects Macs and actions, and approves the assistant. Disconnecting an assistant does not disconnect the Mac from the owner's dashboard. Tokens are restricted to the approved devices/actions, and revocation is checked in D1. High-risk conversation confirmations are a UX rule; independent step-up approval is future work.

The implemented flow validates tokens, issuer/audience/time, exact registered callback URLs, PKCE S256, single-use consent and account ownership. Assistant tokens cannot administer accounts or pairing. Only explicitly provisioned clients in `MUSE_CLIENT_IDS` can reach Muse consent. Production lists one client, described below.

The owner reported submitting the [Muse connector application](https://muse.ai/platform) on September 24, 2026. Review is pending. Muse has used Wand through its web controls; official native OAuth/tool integration must still be registered and tested. See [current status](BUILD_STATUS.md).

## Reviewer account and Muse client

Set up October 5, 2026 for Muse submission `457e4f44-e92b-456e-ac44-69ba01ea6c10`.

**Reviewer sign-in.** Firebase's email/password provider is on, but the relay accepts a password token only when its Firebase UID is listed in `REVIEWER_UIDS` and its email is verified. One account is listed: `reviewer@getwand.app`. Its password was generated on the owner's Mac and lives in the owner's macOS Keychain (item `wand-muse-reviewer`) and in Meta's credentials form, nowhere in this repository. Mail to that address forwards to the owner through Cloudflare Email Routing, which is how a password reset arrives. The dashboard shows a **Reviewer sign-in** link only while a reviewer is listed. There is no public password sign-up or reset screen.

Turning the provider on means anyone can create a password identity in Firebase with the public web key; Firebase's switch to block sign-ups would also block new Google users. Such an identity gets `unauthorized` from every Wand endpoint, so it cannot pair a Mac, see devices or approve a connector. To retire reviewer access, empty `REVIEWER_UIDS` and deploy, then delete the Firebase user.

The reviewer account owns no devices. A reviewer installs Wand and pairs their own Mac; nothing links the account to the owner's Mac.

**Muse client.** `cloud/scripts/register-client.mjs` wrote one public client to production: ID `kqQLjzgKBLLzJ7Ff`, no client secret, PKCE S256 required, single callback `https://agent.meta.ai/api/hatch/oauth/callback`. Dynamic registration stays off. That callback is what Nansen's Muse guide and several public issue reports give for connectors a user adds to Muse. Meta's Connector Platform guidelines and credentials form state no callback, so its use for a reviewed platform connector is an informed assumption, not a Meta-confirmed fact. If Meta uses a different URL, authorization fails closed with `invalid_authorization_request`; register a new client with the right URL and replace the ID.

**Live check, October 5.** A script signed in as the reviewer through Firebase's API and drove production with a simulated device (a pairing record with no Mac behind it). Passed: reviewer token accepted; wrong password refused by Firebase; unverified and verified non-reviewer password accounts refused by the relay, including at pairing and consent; pairing claim, single-use code and redeem; the reviewer could not read, command or revoke a device they had not claimed; `/authorize` refused an unregistered client, three altered callbacks, plain and missing PKCE, an unknown scope, a wrong resource and missing state; no open registration endpoint; consent listed only requested scopes and refused a wider action or an unowned device; the code returned to the exact callback with state; a wrong verifier was refused; the token carried only the approved scope and device, was refused for an unapproved action and on dashboard endpoints; revocation refused the issued access token at once. All test devices, connections and the probe account were removed afterward.

One observation: in one of two runs a refresh request made seconds after revocation still returned tokens, the KV delay described in [the relay notes](../cloud/README.md#two-separate-permissions). In the other run it was refused immediately. Access with a revoked connection is refused through D1 either way.

Not tested: typing the reviewer credentials into the live form in a browser (covered by jsdom tests and the API path only), a reviewer pairing a physical Mac with this account, and any request from Muse itself. Wand requires `resource=https://api.getwand.app/connector` on `/authorize`; whether Muse sends it is unknown.

## Facebook

Facebook provider support and explicit account linking remain implemented, but `FACEBOOK_ENABLED=false` keeps it out of the public flow. Google is the public sign-in path. Earlier Facebook testing and its separate business-verification work do not establish a public Facebook launch or Muse approval.

Before re-enabling Facebook, verify its current provider/publishing state and credential rotation: an app secret was exposed during setup, and the historical setup record did not establish that it was rotated. Never copy secrets into documentation or source. Firebase UID, not a matching email address, identifies the owner of paired devices.
