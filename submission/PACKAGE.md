# Wand connector review package

Updated September 24, 2026. Public Mac release: **Wand 0.13.1, build 34**, signed and notarized. **The Muse connector application has been submitted and is awaiting review**, as confirmed by the owner on this date. Native client registration and end-to-end Muse OAuth/tool testing remain pending; submission is not approval.

## Product

Wand lets an assistant act on a user's own Mac through a menu-bar app. The Mac opens an outbound WebSocket to Wand's relay; no inbound port or separate iPhone app is needed. The intended Muse flow is: install Wand, connect the Mac through Google sign-in, authorize Muse for selected devices/actions, then ask Muse from a phone.

The action catalog includes Mac status, app discovery, sound controls, opening apps and URLs, locking, and browser-tab cleanup. Each device reports its current support, permissions and availability. Poll commands to a terminal result; for desktop input, observe again to verify the requested change. Offline commands fail rather than queue. The acceptance evidence below identifies what has actually been tested on the current release.

The native app supports a fixed action catalog plus locally approved desktop observation and input. Desktop control is powerful: visible app content can be exposed, and GUI actions can change files or run code in an app. See SECURITY.md. Windows/Linux are not released.

## Review links

- Website: https://getwand.app/
- Native download: https://getwand.app/download/ (signed and notarized 0.13.1, build 34; Apple silicon, macOS 26+)
- Release checksum: https://getwand.app/releases/Wand-0.13.1-build34.sha256
- API base: https://api.getwand.app/connector
- OpenAPI: https://api.getwand.app/openapi.json
- OAuth discovery: https://api.getwand.app/.well-known/oauth-authorization-server
- Integration guide: https://getwand.app/developers/
- Reviewer sandbox: https://app.getwand.app/review/
- Support: https://getwand.app/support/
- Privacy: https://getwand.app/privacy/
- Terms: https://getwand.app/terms/
- Brand icon: [assets/wand-512.svg](assets/wand-512.svg)
- Review steps: [REVIEWER-ACCESS.md](REVIEWER-ACCESS.md)
- Security and incident response: [SECURITY.md](SECURITY.md)
- Demo outline and recording status: [DEMO.md](DEMO.md)

No payment is required for this beta. The sandbox uses a reviewer's own Google login and a simulated device. It exercises real hosted pairing, routing, results, offline rejection and revocation without granting access to a personal Mac.

The linked privacy policy and terms are the published legal documents. Their source is in `site/public/privacy/index.html` and `site/public/terms/index.html`; do not substitute an old draft or infer legal review from publication.

## Authentication and registration

Production uses Firebase Google sign-in for owners and a separate Wand OAuth server for assistant clients. Authorization code, PKCE S256, state, the resource `https://api.getwand.app/connector`, and action scopes `wand:<action>` are required. Owners choose permitted Macs and actions. Connector tokens cannot administer the owner's account.

Client admission is manual; there is no public dynamic registration. One public PKCE client (`kqQLjzgKBLLzJ7Ff`) is provisioned and admitted in `MUSE_CLIENT_IDS`, with the callback `https://agent.meta.ai/api/hatch/oauth/callback` that other connector authors report for Muse. We still request Meta's confirmation of the callback and client requirements, then a test of the actual authorization, command-result and image flow. The repository's manifest is an internal description, not a verified Meta import format.

## Current evidence

- Build 34 is Developer ID signed by Thabhelo Duve, team `58XWD3LBSS`, and notarized. App/DMG signatures, stapled tickets and the public-download checksum were verified.
- With build 33 on September 24, Wand's web dashboard and production relay returned real TextEdit observations and a window image. Native inspection independently confirmed 45 input test lines and scrolling from the document's bottom to top. Image-coordinate click and Return-key commands acknowledged delivery; their intended effects were not separately certified. Expired snapshots and changed-window attempts were rejected.
- After confirmed process exit and relaunch, the unchanged installed build reconnected without another password prompt and returned the test document and text through a new relay observation and screenshot. This establishes Keychain, Accessibility and Screen Recording restart persistence on that installation after its signing-identity repairs. See [permission lifecycle evidence](../docs/PERMISSION_LIFECYCLE.md#september-24-owner-signing-build-33).
- Build 33 Focus on/off passed independent Control Center verification. Build 34 candidate tests passed local Safari pinned-tab cleanup and real relay lock/repeated-lock with minimal locked state.
- Final build 34 source `0d7960f` passed CI signing/notarization and exact-artifact signature, staple, Gatekeeper and checksum verification. The contained app was installed with the same designated requirement and reconnected without a permission prompt. Its first Safari and TextEdit image requests passed without manual window raising; two relay-entered lines were independently verified in TextEdit. The native volume display matched the reported volume without changing it. After confirmed exit/relaunch, it reconnected without Keychain or privacy prompts and its first Safari image passed. Disposable fixtures were removed and absence verified; [release evidence](../docs/RELEASE_0_13_1.md) identifies the exact artifact.
- Muse has already used Wand through the web controls in prompt-based testing, as confirmed by the owner; its feedback drove dashboard fixes. This is distinct from registered native OAuth/direct-tool integration.
- Public health, OpenAPI and OAuth discovery endpoints have been checked without login. Unauthenticated connector access returned 401; unknown OAuth clients returned 403. The September 23 run passed 42 Cloudflare runtime tests, including OAuth exchange, PKCE/replay checks, device/action restrictions and revocation. Its test clients were not Meta clients.
- A separate September 24 automated verification run passed 173 tests and 58 shared contract fixtures. These results do not replace physical-device, reviewer-journey or native Muse acceptance.
- The September 24 browser-sandbox run passed status, mute, unapproved-Shortcut rejection, approved Shortcut execution, offline rejection, reconnect, repeated lock, minimal locked state, rejection of mute while locked, and revocation. A discovered old-socket status race was corrected and deployed; status commands succeeded after reconnect and several minutes while the page remained online. All task-created review devices were revoked, with final revocation confirmed by the page and controls hidden. Simulated results do not establish physical Mac execution.
- A live support-form test sent September 24 at 07:23:42 UTC was received in the operator's inbox. Branded HTML and plain-text alternatives were present, and Gmail reported SPF, DKIM and DMARC passing. See [support verification](../docs/SUPPORT_FORM.md#september-24-2026-live-delivery-check).

## Limits disclosed for review

Fresh-user or second-Mac installation and a full Mac reboot have not been revalidated for the owner signing identity. A second sleep test verified about 43 seconds of actual sleep followed by an online, unlocked Mac in the dashboard. The owner confirmed waking the Mac manually before the 75-second missed-heartbeat interval, so live offline-state and recovery behavior at that threshold remain unverified; this was not an unintended wake. See [desktop acceptance](../docs/DESKTOP_ACCEPTANCE.md#september-24-build-34-release-results) for the bounded results. Capability discovery is required before dispatch; signing and notarization do not establish action availability.

Native Muse OAuth authorization and direct tool-result/image compatibility await verified registration details. No recorded native-connector demo is available, and the marketing animation is not execution evidence. [DEMO.md](DEMO.md) describes a short recording of the existing web-to-Mac flow; recording that outline does not establish native Muse integration.

## Submitted review scope

Wand connects an assistant to a user's own Mac through a signed, notarized menu-bar app and an outbound relay connection. The public beta provides Mac status and app controls, plus locally approved desktop observation and input. Owners control device/action consent and can pause or revoke access. We are requesting review of the deployed API, OAuth service, reviewer sandbox and Mac beta, together with verified Muse client/callback requirements so we can complete native authorization and tool-result testing.
