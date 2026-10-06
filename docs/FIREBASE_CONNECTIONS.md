# Account sign-in and assistant authorization

Wand uses **Firebase Authentication** for account identity: Google sign-in, or an email address and password (described below) and Cloudflare D1 for the device registry. Production does not use Auth0 or Firestore. `getwand.app` and the Mac app both send account setup to `app.getwand.app`; the Mac stores device credentials in Keychain and needs neither a Firebase SDK nor Google tokens.

## Assistant connection

Wand OAuth is separate from Google sign-in: the owner signs in, selects Macs and actions, and approves the assistant. Disconnecting an assistant does not disconnect the Mac from the owner's dashboard. Tokens are restricted to the approved devices/actions, and revocation is checked in D1. High-risk conversation confirmations are a UX rule; independent step-up approval is future work.

The implemented flow validates tokens, issuer/audience/time, exact registered callback URLs, PKCE S256, single-use consent and account ownership. Assistant tokens cannot administer accounts or pairing. Only explicitly provisioned clients in `MUSE_CLIENT_IDS` can reach Muse consent. Production lists one client, described below.

The owner reported submitting the [Muse connector application](https://muse.ai/platform) on September 24, 2026. Review is pending. Muse first connected natively through Wand OAuth on October 5, 2026, [recorded below](#native-muse-connection-october-5). See [current status](BUILD_STATUS.md).

## Email and password accounts

Public since October 5, 2026, alongside Google. `PASSWORD_ENABLED` in the relay configuration is the switch: set it to anything but `true` and deploy, and the relay refuses every password token and the dashboard hides the option.

- **Sign-up and sign-in.** On app.getwand.app, **Use email instead** opens a form with Sign in, Create account and Forgot password. Firebase stores the password hash; the relay only ever sees Firebase ID tokens.
- **Confirmed email required.** The relay answers `email_not_verified` (403) to any password token whose `email_verified` claim is not true, on every account endpoint, so an unconfirmed account cannot list devices, preview or claim a pairing code, open connector consent or send a command. The dashboard shows a confirmation screen with a resend button instead of the workspace. A token issued before confirmation stays refused; the dashboard fetches a fresh one.
- **Password reset.** Firebase emails a reset link. The dashboard gives the same reply whether or not the address has an account.
- **No merging by email.** A device belongs to a Firebase UID. Signing up with an address that already has an account fails with a message to use the original sign-in. A second method is added only from Account settings while signed in: **Add a password** for a Google account, **Add Google sign-in** for a password account. Linking a Google identity that already belongs to another Wand account fails; the two accounts stay separate.
- **One Firebase behaviour to know.** The project keeps Firebase's default of one account per email. If someone signs in with Google using an address that already has a password account, Firebase attaches Google to that same account (and drops an unconfirmed password). Wand does not do this and cannot turn it off without allowing duplicate emails, which would remove the email claim Google sign-in relies on. No devices move between accounts either way, and an unconfirmed account holds nothing to take over.
- **Password length.** The dashboard asks for at least 10 characters. Firebase itself enforces only 6; a stricter server rule needs the Identity Platform upgrade, which this project does not have.

Verified October 5 (relay `3b25b41a-298b-45e5-84fb-05b7acaa8c68`, website `e1325d55-03dc-4080-abea-34744571a03c`): all **58 cloud tests** and **65 website tests** passed. A live production script created a probe account through Firebase's public sign-up API and confirmed that it was refused with `email_not_verified` at devices, pairing preview and claim, consent, connections and commands; that Firebase accepted the confirmation-email and reset requests and answered a reset for an unknown address identically; that sign-up with an existing account's address was refused; that after its email was marked confirmed (through the admin API, not by opening the emailed link) a fresh token was accepted while the old one stayed refused; and that a simulated device paired by the probe could not be seen, read, commanded, renamed or disconnected by the reviewer account. The probe account and device were deleted. The owner's existing Google session kept working on the new build.

Not verified live: the forms in a real browser, opening a real confirmation or reset link, and either linking direction. Those paths are covered by jsdom tests against a stubbed sign-in client only.

## Reviewer account and Muse client

Set up October 5, 2026 for Muse submission `457e4f44-e92b-456e-ac44-69ba01ea6c10`.

**Reviewer account.** `reviewer@getwand.app` is an ordinary password account whose email is already confirmed. Its password was generated on the owner's Mac and lives in the owner's macOS Keychain (item `wand-muse-reviewer`) and in Meta's credentials form, nowhere in this repository. Mail to that address forwards to the owner through Cloudflare Email Routing; Cloudflare's log shows a Firebase reset email forwarded and delivered on October 5, though its arrival in the owner's inbox was not confirmed. The account owns no devices. A reviewer installs Wand and pairs their own Mac; nothing links the account to the owner's Mac.

**Muse client.** `cloud/scripts/register-client.mjs` wrote one public client to production: ID `kqQLjzgKBLLzJ7Ff`, no client secret, PKCE S256 required, single callback `https://agent.meta.ai/api/hatch/oauth/callback`. Dynamic registration stays off. The callback was taken from Nansen's Muse guide and several public issue reports, because Meta's Connector Platform guidelines and credentials form state none. Muse's own authorization requests on October 5 used exactly that URL, as recorded below. Meta has not documented it for reviewed platform connectors, so a different URL during Meta's review would fail closed with `invalid_authorization_request`; register a new client with that URL and add its ID.

**Live check, October 5** (run while password sign-in was still limited to the reviewer; the OAuth code has not changed since). A script signed in as the reviewer through Firebase's API and drove production with a simulated device (a pairing record with no Mac behind it). Passed: reviewer token accepted; wrong password refused by Firebase; unverified and verified non-reviewer password accounts refused by the relay, including at pairing and consent; pairing claim, single-use code and redeem; the reviewer could not read, command or revoke a device they had not claimed; `/authorize` refused an unregistered client, three altered callbacks, plain and missing PKCE, an unknown scope, a wrong resource and missing state; no open registration endpoint; consent listed only requested scopes and refused a wider action or an unowned device; the code returned to the exact callback with state; a wrong verifier was refused; the token carried only the approved scope and device, was refused for an unapproved action and on dashboard endpoints; revocation refused the issued access token at once. All test devices, connections and the probe account were removed afterward.

One observation: in one of two runs a refresh request made seconds after revocation still returned tokens, the KV delay described in [the relay notes](../cloud/README.md#two-separate-permissions). In the other run it was refused immediately. A token obtained that way cannot reach the connection: `tests/connections.test.js` revokes a connection while its grant still exists, refreshes successfully and confirms the new token is refused on every connector endpoint.

Not tested: typing the reviewer credentials into the live form in a browser (covered by jsdom tests and the API path only) and a reviewer pairing a physical Mac with this account.

## Native Muse connection, October 5

Two kinds of evidence are recorded here and should not be confused.

**Read from production records** (D1 and KV, October 5): after the simulated check above, Muse sent a real authorization request with client `kqQLjzgKBLLzJ7Ff`, redirect `https://agent.meta.ai/api/hatch/oauth/callback`, resource `https://api.getwand.app/connector` and all 19 `wand:` scopes. Connections were approved at 23:00 UTC with one action and at 23:48 UTC with all 19, both through that client. It remained the only registered client, and relay version `3b25b41a-298b-45e5-84fb-05b7acaa8c68` was serving. So Muse uses the registered callback and sends the `resource` value Wand requires.

**Reported by the owner's testing session the same day, not re-run for this record:** through the native connection Muse passed device discovery, capabilities and status; volume changes and mute, restored afterward; opening, focusing and closing Calculator, including the already-open and already-closed results; opening a URL; viewing TextEdit screenshots, clicking at image coordinates, typing, pressing Return and scrolling; rejection of unsafe URLs, unallowlisted Shortcuts and invalid or reused desktop snapshots; and staying authorized past the 15-minute access-token lifetime without a second consent. The owner verified lock, sleep, playback, allowlisted Shortcuts, Focus and reconnect directly.

Open from that session: Safari's native cleanup run was interrupted when Safari was closed, so it is inconclusive (earlier pinned-tab testing passed), and one transient authentication error recovered during polling without a known cause. Exact per-action evidence belongs in [DESKTOP_ACCEPTANCE.md](DESKTOP_ACCEPTANCE.md).

This was the owner's own Muse account and Mac. It is not Meta's review, a reviewer's Mac or a fresh installation.

## Facebook

Facebook provider support and explicit account linking remain implemented, but `FACEBOOK_ENABLED=false` keeps it out of the public flow. Google is the public sign-in path. Earlier Facebook testing and its separate business-verification work do not establish a public Facebook launch or Muse approval.

Before re-enabling Facebook, verify its current provider/publishing state and credential rotation: an app secret was exposed during setup, and the historical setup record did not establish that it was rotated. Never copy secrets into documentation or source. Firebase UID, not a matching email address, identifies the owner of paired devices.
