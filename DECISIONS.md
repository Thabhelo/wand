# Decisions — 2026-09-20

- Contracts: JSON Schema 2020-12 as the language-neutral source; Python validation wrapper now, Swift conformance adapter in Phase 1.
- Relay: Python 3.12 + FastAPI, one async process for MVP; straightforward shared validation and async WebSockets. Not implemented yet.
- Auth: Auth0 Authorization Code + PKCE; validate access-token signature, algorithm allowlist, issuer, audience, expiry and subject through a provider interface. Never accept ID tokens as API authorization. Tenant and Muse OAuth interoperability remain unconfigured.
- Persistence: SQLite behind a repository interface. One Fly Machine and one worker with a persistent volume; socket registry in memory cannot route across workers. Disable autostop. Render persistent disk is fallback. No free-tier assumption or purchase authorization.
- macOS floor: 26, with 26 and 27 as target major releases based on Apple's current security-release page. Local inspection found 26.6.2 and Swift 6.4; no 27 action testing is claimed.
- Pairing: bootstrap secret authorizes enrollment only. Device generates its durable 256-bit token into Keychain before redeeming a claimed code; relay stores its hash. This avoids persisting or retransmitting a server-generated raw token after a lost handoff response.
- Prompt amendments: add authenticated bootstrap redemption, `delivered` WS event, command expiry, explicit management endpoints, redacted locked-state response, and redacted persisted params. See contract review.
- Confirmation: high-risk actions and closing tabs always require explicit confirmation. Medium actions otherwise execute and narrate. Confirmation instructions do not cryptographically prove human consent.
- State minimization: no state payload persistence; action results retained briefly for polling in memory. Stored command result is null for get_state. Audit stores status only and redacts all params.
- Safety: fail closed when lock status cannot be determined; locked devices disclose only get_state and acknowledge idempotent lock_screen without executing it. Unknown API support returns action_unsupported rather than substituting synthetic keystrokes or a shell.
- Review: user approved Phase 0 with eight amendments on 2026-09-20; incorporated revoke_self/pending UI, deletion cascade, idempotent lock, local forensics, expiry/dedup limits, bounded pairing polling, v2 step-up, and client/hello hardening. Phase 1 protocol work is authorized.
- Phase 1: build test-only Python device/relay peers before Swift protocol client. Probe uses simulated actions and memory-only test credentials; it cannot control the Mac. Production Keychain/menu-bar/OS integration remains a separate slice.
- V2: out-of-band step-up confirmation for high-risk actions, bound to the exact command; OAuth per-client action policy is reserved now. See review packet for the trust boundary.

## Current sources and unresolved evidence

- [Meta Muse product page](https://ai.meta.com/muse/) describes connectors. Exact third-party submission schema, OAuth requirements, review URL and directory rules remain unverified. Muse Code's MCP docs are a separate product and do not establish iOS connector compatibility.
- [Apple security releases](https://support.apple.com/en-us/100100) lists macOS 27 and 26.7 in September 2026. Availability of each action on both systems still requires empirical spikes.
- [Auth0 backend authorization](https://auth0.com/docs/quickstart/backend/django) documents JWKS access-token validation; the planned FastAPI implementation must independently test issuer/audience validation and key rotation.
- [Fly autostop lifecycle](https://fly.io/docs/reference/fly-proxy-autostop-autostart/) informs the single always-running service choice.

Do not claim first physical-device connector, guaranteed featuring, verified platform acceptance, or any deployed acceptance pass without evidence.

## Phase 1 observations — 2026-09-20

- Direct Swift compiler fallback verifies the protocol while the installed SwiftPM ManifestAPI fails linking; no toolchain repairs attempted. XCTest is absent, so explicit standalone throwing checks cover policy behavior.
- Read-only discovery: prompt CGSession path absent and neither installed browser dictionary declares a pinned tab property. Keep these OS features unimplemented until verified; no guessed fallback.
- Close handshake: revoke stops commands immediately, but the Swift client waits for the relay-owned 4003 close rather than invalidating URLSession immediately and racing its close frame.
- Full local params are the forensic source; cloud metadata stays redacted. Production local log idle-retention/clear/export UI remains required.

## Xcode unblock — 2026-09-20

- User installed and opened Xcode 27.0 (27A266a), now selected as the developer directory. Standard SwiftPM manifest/build succeeds. Xcode-built binaries pass 8 policy checks, 58 shared fixtures and 27 contract/integration tests. Prior toolchain blockage is resolved; direct compiler build remains an optional fallback.
- No real lock/sleep/tab actions were executed during toolchain verification. Remaining OS API and macOS 27 runtime checks are unchanged.

## Native Lab build — 2026-09-20

- Added a separate `local.macbridge.lab` LSUIElement app so the owner can inspect a test panel without enabling remote control. Simulated state and outcomes are labeled; no live executor, relay connection or production credentials exist in this app.
- CGSession console/login flags are not lock status. Real action execution stays disabled while the lock-state API remains unverified.
- Session generation changes on sleep/wake/user-switch notifications; stale generation checks are unit tested. Actual lifecycle behavior on 26/27 still needs an empirical session.
- Keychain Generic Password wrapper is built; its GUI round-trip is user-initiated and temporary. It has not been exercised yet.
- SwiftPM native XCTest now works with full Xcode: four new tests passed. GUI inspection encountered crashes in SkyComputerUseService; interface verification remains pending.
- Ad-hoc local package signature verified. Packaging supports explicit Developer ID + Keychain notary-profile DMG flow, not executed without those credentials.

- Packaging follow-up: use the temporary test folder for the signed Lab artifact; Finder/iCloud added disallowed metadata to the Documents copy. Strip only generated-bundle FinderInfo/ResourceFork before signing, preserve quarantine, and verify the final temporary copy. A process check confirms the test app launches; computer-use service crashes still block visual QA.

## 2026-09-20 — Build across components without phase handoffs
- User explicitly requested completing the connected implementation before further phase reviews. Proceed across agent, relay, dashboard, connector and submission artifacts.
- FastAPI with Auth0 RS256 JWT validation; no production fake-auth switch. Tests inject synthetic authentication separately.
- Single-process SQLite repository for this build; production multi-process deployment remains prohibited until distributed connection ownership exists.
- Ship a separate real MacBridge target alongside the existing Lab. The real target pairs over HTTPS, uses Keychain and WSS, and binds its local API only to 127.0.0.1.
- Keep unsupported/unverified OS capabilities as explicit errors, never simulated successes in the production agent. The lock-state guard remains unknown and blocks all real actions until empirical verification.
- Isolated loopback reviewer sandbox uses the real relay with a synthetic device and a prominent simulation banner. It is not a deployment or evidence of physical actions.
- Meta's public platform page confirms review stages but not the full OAuth/manifest contract; submission artifacts remain drafts.


## 2026-09-20 — Replace blanket unknown with conservative native signal checks
- Empirical read-only spike on macOS 26.6.2 found an explicit IOConsoleLocked=false while the current user was the unique active console session; per-session lock keys were absent. Use the explicit root boolean, never absence-as-false.
- Require CGSession and IOConsoleUsers to agree on active UID. Missing, ambiguous, numeric-not-boolean and contradictory data remain unknown; inactive sessions cannot operate on another user's console.
- This is an undocumented OS implementation signal, not an Apple API stability promise. True lock/unlock transitions and macOS 27 must still be physically verified before release.
- Real get_state uses the same native execution boundary in the app and empirical probe. The UI now exposes a local read without requiring cloud credentials. The guard is rechecked after collection before releasing state.


## 2026-09-20 — Repair the installed interactive application
- User reported Read this Mac produced no visible result. The installed local API returned real state, so native executor tests alone were insufficient evidence of the user flow.
- Replaced the scene-based window with explicit AppKit lifecycle and target/action buttons. Retained LSUIElement and the menu bar. Visible app verification now shows real state and success feedback.
- Do not count a build/probe as a verified button interaction; inspect the actual installed window and separate unavailable remote capabilities from working local controls.

- 2026-09-20: Keep the repaired AppKit event lifecycle and use four native pages rather than reintroducing the unresponsive SwiftUI scene. Real local controls remain independent of hosted setup.
- 2026-09-20: Add explicit target-naming confirmations to local quit/Shortcut controls. These are a local UX boundary, not evidence of independent authorization for relay commands.
- 2026-09-20: Verify the Shortcuts CLI option terminator with a nonexistent leading-hyphen name, then pass all approved names after `--`; no shell string construction.
- 2026-09-20: Production relay origin is baked into the signed agent; custom service settings are Advanced-only. No guessed Muse OAuth/deep link is shipped.
- 2026-09-20: Handoff uses a short-lived pairing code in a URL fragment, with explicit account/device review before claim. Bootstrap/device tokens never enter the handoff URL.
- 2026-09-20: Add authenticated `ready` protocol acknowledgment and bootstrap-authenticated enrollment cancellation; opening a browser or sending hello is insufficient evidence of connection.

## 2026-09-20 — Free-tier hosted relay and web controls
- Production target changes to Cloudflare Workers, D1 registry and one SQLite Durable Object per Mac. The Python relay stays a local reference, not a second production service.
- Token hashes/pairing/ownership live in D1. Per-device Durable Objects own hibernating sockets, command metadata and redacted audits. Results stay in memory for at most 60 seconds and can expire sooner on eviction.
- The agent adds a public X-Wand-Device-ID upgrade header for routing; it grants no access. The existing hello token must match that device.
- Auth0 remains free-plan compatible, fail-closed until a real tenant/client is configured. No password auth or test-token bypass is deployed.
- Web controls require confirmed results, name the target in high-risk confirmations, disable offline controls and keep only action names in session history.

- 2026-09-20: Expose the actual relay OpenAPI at `/openapi.json`; omit invented OAuth endpoints while configuration is absent.
- 2026-09-20: Now-playing reads must use already-running, already-authorized apps; get_state must never open a permission dialog or launch a player.
- 2026-09-20: Recover interrupted enrollment by cancelling with the existing Keychain bootstrap token before allowing a new enrollment.

- 2026-09-20: Firebase Google sign-in replaces Auth0 for production dashboard identity, per owner approval; dedicated `wand-getwand` project belongs to thabheloduve@gmail.com and stays on Spark.
- 2026-09-20: Assistant authorization is separate Wand OAuth using Cloudflare's maintained provider, with explicit device/action consent and D1 revocation checks. Firebase login alone grants no assistant access.
- 2026-09-20: Muse client registration stays closed until a verified platform callback/client is available; no invented Meta endpoint or publicly self-declared Muse clients.

- 2026-09-20: Owner supersedes the permanent product exclusion of remote unlock: investigate an explicitly opted-in, separately approved implementation. This changes roadmap intent only; current protocol still rejects unlock until an OS-supported implementation is verified. See docs/REMOTE_UNLOCK_RESEARCH.md.
