# Wand

**We gave Muse more powers.** Wand connects a Mac to an assistant through an outbound device connection, a cloud relay, and a web dashboard. No separate iPhone app is required.

## Project layout

- `agent/`: Swift menu-bar app, native actions, Keychain storage, and local API.
- `cloud/`: production Cloudflare relay, D1 registry, Durable Object WebSockets, migrations, and tests.
- `web/`: canonical account and device dashboard.
- `site/`: public website and dashboard hosting. Dashboard assets sync from `web/` before deployment.
- `contracts/`: shared action catalog, schemas, and transport rules.
- `connector/`: OpenAPI, action manifest, and operator instructions.
- `relay/` and `harness/`: Python reference relay and isolated device simulator.
- `submission/`: security, legal, and reviewer-package drafts.

## Current status

The website, dashboard, and Cloudflare relay are deployed at [getwand.app](https://getwand.app), [app.getwand.app](https://app.getwand.app), and [api.getwand.app](https://api.getwand.app). The Mac app is a local, ad-hoc signed development build.

Real sign-in still requires hosted-auth configuration. Muse registration, complete physical-device acceptance tests, remaining macOS actions, and Apple signing/notarization are unfinished. Simulated results do not demonstrate real device control. See [launch status](deploy/WAND_LAUNCH.md) and [cloud setup](cloud/README.md).

## Develop the cloud relay and website

Use Node.js 22 or 24 LTS. In `cloud/`, run `npm ci`, then `npm test` or `npm run dev`. In `site/`, run `npm ci`, then `npm run check` or `npm run dev`. Configure your own Cloudflare bindings and hosted-auth settings before deploying; never commit credentials.

Dashboard checks run from the repository root:

```sh
node tests/onboarding.mjs
```

## Build the Mac app

Requires macOS and Xcode:

```sh
swift build --package-path agent
swift test --package-path agent
python3 scripts/package_agent.py --binary agent/.build/debug/MacBridge --relay-origin https://api.getwand.app --dashboard-origin https://app.getwand.app
```

The packaged app is `dist/Wand.app`. Packaging defaults to an ad-hoc signature for local testing. Developer ID signing and notarization require your own Apple credentials; see the packaging script options. Device and local API tokens stay in Keychain.

## Run the isolated reviewer sandbox

```sh
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m harness.sandbox
```

Open http://127.0.0.1:8787/sandbox. This runs the reference relay with a synthetic device and never controls your Mac. Restart after simulated locking or revocation to create a fresh device. Production does not accept the sandbox identity.

```sh
.venv/bin/python -m unittest discover -s tests -v
PYTHONPATH=. .venv/bin/python scripts/build_connector.py
```

## Security

No remote unlock, arbitrary shell endpoint, screenshots, or synthetic typing. Actions use a closed catalog, validated parameters, token revocation, and command expiry. The relay sees command contents in this version. Read the [security model](submission/SECURITY.md) for boundaries and residual risks.

Source, tests, assets, and deployment definitions belong in Git. Local secrets, dependencies, databases, and generated app installers do not.
