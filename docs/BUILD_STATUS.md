# Wand status

Updated **October 5, 2026**. This is the current status page; dated acceptance records describe the exact build and path tested, not a rolling claim that every action was retested.

## Shipped

| Component | Current state |
| --- | --- |
| Mac app | **0.13.1, build 34**, Apple-silicon/macOS 26+ public beta; owner Developer ID signing and Apple notarization verified. Direct download, not a Mac App Store listing. |
| Website and dashboard | Live at [getwand.app](https://getwand.app) and [app.getwand.app](https://app.getwand.app), with the [Wand blog](https://getwand.app/blog/). |
| Backend | Cloudflare Workers, D1 and per-device Durable Objects at `api.getwand.app`; Firebase sign-in with Google or with a confirmed email and password. Python/FastAPI is the reference implementation only. |
| Pairing | Connect in Wand → sign in → approve the Mac. The setup link carries the code; manual code entry is a fallback. |
| Actions | Status, audio/media, app discovery/open/close, URLs, allowlisted Shortcuts, lock, sleep, browser cleanup, Focus and permissioned desktop tools are implemented. Per-device capabilities determine current availability. |
| Native permissions | Build 34 retained the owner's signing identity and reconnected after an app restart without new Keychain or privacy prompts in the recorded test. macOS owns permissions; this is not a promise that prompts can never recur. |
| Release workflow | GitHub signing, notarization and publication succeeded for build 34 using the owner's team. Ebuka's credentials are no longer the current release dependency. |
| Muse application | **Submitted and awaiting review**, reported by the owner on September 24. This records the owner's confirmation; it is not a Meta approval receipt. |
| Muse connection | **Native connection made October 5.** Muse authorized through Wand OAuth with the registered client, callback and resource, and the owner's session reports passing native tests of discovery, status, audio, apps, URLs and desktop observation and input. This is a connection from the owner's own Muse account, not Meta's directory approval. [Evidence and what is owner-reported](FIREBASE_CONNECTIONS.md#native-muse-connection-october-5). |

## Latest verified changes

- October 5: first native Muse connection. Production records show Muse authorizing with client `kqQLjzgKBLLzJ7Ff`, the callback `https://agent.meta.ai/api/hatch/oauth/callback` and the resource `https://api.getwand.app/connector`, with connections approved at 23:00 and 23:48 UTC. That settles the callback and resource questions. The owner's testing session reports the action results; they were not re-run for this entry. [Details](FIREBASE_CONNECTIONS.md#native-muse-connection-october-5).

- October 5: public email and password accounts, a Muse reviewer account and a registered Muse OAuth client. Relay version `3b25b41a-298b-45e5-84fb-05b7acaa8c68`, website version `e1325d55-03dc-4080-abea-34744571a03c`. All **58 cloud tests** and **65 website tests** passed. Live production checks with simulated devices passed sign-up, refusal of unconfirmed accounts at pairing and consent, acceptance after confirmation, isolation between accounts, consent, scope limits and revocation. Not tested: the forms in a real browser, a real confirmation or reset link, account linking and a reviewer's own Mac. [What was set up, the evidence and the limits](FIREBASE_CONNECTIONS.md#email-and-password-accounts).

- September 25: published the first [architecture post](https://getwand.app/blog/your-ai-your-mac/) with an interactive command-flow diagram, RSS, canonical/sitemap entries and an X preview image. Desktop and 320/390 px layouts verified; **56 website tests** passed. Blog sources and publishing steps are in `site/README.md`.

- Relay database fix `1546525`: heartbeat scheduling, timeouts and reconnect handling now skip completed command history through a partial index. All **55 cloud tests** passed. Deployment and a real Mac status command were verified; initial live idle reads dropped from 2,592–3,888/minute to 22/minute. No Mac update, new permissions or shorter audit retention is needed. [Implementation, migration tests and production evidence](../cloud/README.md#database-read-costs).
- Native release source `0d7960f`, publication `59e4a6d`: [build 34 artifact and test evidence](RELEASE_0_13_1.md), including CI notarization, window capture, text input and restart persistence.
- Website source `7e0b398`: repeated volume arrow keys retain focus; the selected Mac shows its reported version/build. All **54 website tests** passed. Live volume changes **50% → 51% → 53%** were confirmed without refocusing, then restored to **50%**. Website deployment: `2918cddf-53a4-4df0-b212-61e450c557f8`.
- Lock and repeated lock passed through the production relay on the build 34 candidate. Safari pinned-tab preservation passed through the local action path. Focus on/off has independently verified results. Sleep and reconnect passed; the owner manually woke the Mac after about 43 seconds. These are implemented actions, not unfinished OS work. [Detailed acceptance and path limits](DESKTOP_ACCEPTANCE.md).

## Remaining checks and dependencies

1. Meta's review outcome. A native connection from the owner's Muse account works; directory approval is a separate decision. From the October 5 native session: Safari's native cleanup run was interrupted and is inconclusive, and one transient authentication error recovered during polling and is worth investigating.
2. Fresh-user or second-Mac installation, a full Mac reboot under the current signing identity, and the live 75-second missed-heartbeat/offline interval. The manual wake ended the sleep test before that interval; it was not an unintended wake.
3. Broader compatibility: Chrome's dedicated cleanup, Safari cleanup without pinned preservation, other macOS versions/locales, and representative app workflows. Existing passes do not certify every app or action combination.

The current release remains a **public beta**. Signing/notarization, Muse review, and Mac App Store publication are separate processes.

## Where to look

- [Action catalog](../contracts/actions.json), [capability contract](../contracts/CAPABILITIES.md), [OpenAPI](../connector/openapi.json).
- [Release workflow](AUTOMATED_RELEASES.md), [permission lifecycle](PERMISSION_LIFECYCLE.md), [cloud deployment](../cloud/README.md).
- [Submission package](../submission/PACKAGE.md), [reviewer access](../submission/REVIEWER-ACCESS.md), [security model](../submission/SECURITY.md).

Update this page when a release, deployment, acceptance result or submission status changes. Keep exact test evidence in the acceptance/release documents; remove superseded blocker lists instead of appending contradictory updates.
