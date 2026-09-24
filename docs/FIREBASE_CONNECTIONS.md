# Account sign-in and assistant authorization

Wand uses **Firebase Google sign-in** for account identity and Cloudflare D1 for the device registry. Production does not use Auth0 or Firestore. `getwand.app` and the Mac app both send account setup to `app.getwand.app`; the Mac stores device credentials in Keychain and needs neither a Firebase SDK nor Google tokens.

## Assistant connection

Wand OAuth is separate from Google sign-in: the owner signs in, selects Macs and actions, and approves the assistant. Disconnecting an assistant does not disconnect the Mac from the owner's dashboard. Tokens are restricted to the approved devices/actions, and revocation is checked in D1. High-risk conversation confirmations are a UX rule; independent step-up approval is future work.

The implemented flow validates tokens, issuer/audience/time, exact registered callback URLs, PKCE S256, single-use consent and account ownership. Assistant tokens cannot administer accounts or pairing. Only explicitly provisioned clients in `MUSE_CLIENT_IDS` can reach Muse consent; the committed production configuration leaves that list empty pending verified Meta registration details.

The owner reported submitting the [Muse connector application](https://muse.ai/platform) on September 24, 2026. Review is pending. Muse has used Wand through its web controls; official native OAuth/tool integration must still be registered and tested. See [current status](BUILD_STATUS.md).

## Facebook

Facebook provider support and explicit account linking remain implemented, but `FACEBOOK_ENABLED=false` keeps it out of the public flow. Google is the public sign-in path. Earlier Facebook testing and its separate business-verification work do not establish a public Facebook launch or Muse approval.

Before re-enabling Facebook, verify its current provider/publishing state and credential rotation: an app secret was exposed during setup, and the historical setup record did not establish that it was rotated. Never copy secrets into documentation or source. Firebase UID, not a matching email address, identifies the owner of paired devices.
