# Firebase and Muse connection — 2026-09-20

Wand uses Firebase Google sign-in for its account dashboard and Cloudflare D1 for its device registry. No Firestore database or Auth0 tenant is needed. `getwand.app` sends account setup to `app.getwand.app`; the native app opens the same setup page, so there is one account identity rather than a second native login.

The assistant connection is separate OAuth consent: sign in, choose Macs, choose actions, Allow Muse. Users can disconnect Muse without disconnecting the Mac from Wand. High-risk conversation confirmations are a UX policy, not a security boundary. Out-of-band approval is still a future feature.

Implemented and tested: token signature/issuer/audience/timestamp checks, closed Google/Facebook-provider allowlist, exact client callback validation, PKCE S256, single-use consent, cross-account rejection, action/device restrictions, no assistant administration rights, narrowed token scope, immediate D1 revocation, account-deletion cascade, scoped command-result polling.

Operational dependency: Meta/Muse's genuine connector registration and verified callback URL are not available in this workspace. Do not set an invented callback or claim an approved Muse listing. Only explicitly provisioned clients listed in MUSE_CLIENT_IDS can reach consent.

The live native app does not need a Firebase SDK or Google tokens in Keychain. Its device-pairing protocol is unchanged. Native actions that remain blocked by OS verification are not made functional by this authentication change.

Facebook sign-in and explicit account linking are enabled. Firebase provider configuration for Meta app 1402697268050010 was verified on 2026-09-20 and the live button is visible. A completed Facebook sign-in and Meta public availability still need verification. Facebook email verification is not used as proof of device ownership: the Firebase UID remains the sole account key.

Official platform discovery: https://muse.ai/platform — Submit a connector opens a sign-in-gated form. The public page confirms functional, security and legal review before directory listing; no OAuth callback address is published there.
