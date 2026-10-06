# Wand

**We gave Muse more powers.** Wand lets an assistant control a Mac through a menu-bar app, an outbound device connection, a cloud relay and a web dashboard. No separate iPhone app is required.

## Current status

**Public beta: Wand 0.13.1, build 34**, signed with the owner's Developer ID and notarized by Apple. [Download Wand](https://getwand.app/download/) for Apple silicon and macOS 26+. The [website](https://getwand.app), [dashboard](https://app.getwand.app) and [relay](https://api.getwand.app/healthz) are live. Google and confirmed email/password sign-in, pairing and remote web controls work.

The owner submitted the Muse connector application on **September 24, 2026**; it is awaiting review. Muse has used Wand through the web controls and, since October 5, through a native OAuth connection from the owner's Muse account. Meta's directory approval is separate. [Native action test evidence](docs/NATIVE_MUSE_ACCEPTANCE.md) distinguishes independently verified results from owner-confirmed passes.

[Current status and remaining checks](docs/BUILD_STATUS.md) is the single release-status source. See [build 34 evidence](docs/RELEASE_0_13_1.md) for the exact artifact and [desktop acceptance](docs/DESKTOP_ACCEPTANCE.md) for tested actions and limits. Older build notes are retained in Git history, not as active checklists.

The relay's background checks skip completed command history to reduce database reads. This server update needs no Mac reinstall or permission changes; [55 cloud tests cover the fix and existing behavior](cloud/README.md#database-read-costs).

## Project layout

- `agent/`: Swift menu-bar app, native actions, Keychain storage and loopback API.
- `cloud/`: production Cloudflare Workers relay, D1 registry and Durable Object WebSockets.
- `web/`: canonical account/device dashboard. `site/` hosts it, the public website and the [Wand blog](https://getwand.app/blog/); deployment syncs dashboard assets from `web/` and builds posts from `site/content/blog/`.
- `contracts/`: shared action catalog, schemas and transport rules.
- `connector/`: OpenAPI, action manifest and operator instructions. [policy.md](policy.md) guides assistant operation.
- `submission/`: review materials, security model and reviewer access.
- `relay/` and `harness/`: Python reference implementation and isolated simulator, not the production backend.

## Develop

Use Node.js 22 or 24 LTS. From the repository root:

```sh
npm ci --prefix cloud
npm test --prefix cloud
npm ci --prefix site
npm run check --prefix site
node tests/onboarding.mjs
```

Run `npm run dev` in `cloud/` or `site/` for local development. See [cloud setup](cloud/README.md) and [website setup](site/README.md); use your own provider bindings and keep secrets out of Git.

For the Mac app, use macOS 26+ and Xcode:

```sh
swift build --package-path agent
swift test --package-path agent
```

Local packaging defaults to an ad-hoc development signature. Public builds use the configured [automated signing and notarization workflow](docs/AUTOMATED_RELEASES.md). Keep the bundle identifier, signing team and installation path stable across updates; see [permission guidance](docs/PERMISSION_LIFECYCLE.md).

## Review and security

The hosted [review sandbox](https://app.getwand.app/review/) uses real authentication and relay transport with a clearly labeled simulated Mac. See [reviewer instructions](submission/REVIEWER-ACCESS.md). Simulation does not prove physical-device behavior.

Actions use a closed catalog, validated parameters, expiry and revocation. Desktop control can read app contents, capture app-window images and send input after local consent and macOS permissions. It is broader than the minimized status endpoint; it can operate a terminal, so it must not be described as unable to run code. No dedicated arbitrary-shell or remote-unlock endpoint exists. The relay can read payloads in this version. Read the [security model](submission/SECURITY.md).

Keep source, tests, assets, deployment definitions and the published installer/checksum in Git. Keep local credentials, dependencies, databases and disposable build output out.
