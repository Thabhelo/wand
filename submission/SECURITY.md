# Wand security and incident response

Updated September 24, 2026. Describes the current Cloudflare/Firebase implementation and Wand 0.13.1, build 34. The repository also retains an older FastAPI reference; its Auth0 and process-local limiter descriptions do not describe the deployed service.

## Identity and access

Owners sign in through Firebase Authentication with Google or with an email and password. A password account is refused everywhere until its email is confirmed, and accounts are never joined by matching email. Assistant clients use a separate OAuth authorization-code flow with PKCE S256, exact registered HTTPS callbacks, state, resource binding, and device/action consent. Only manually admitted clients can authorize. Firebase tokens cannot call connector endpoints; connector tokens cannot administer accounts. Access tokens last 15 minutes; refresh grants last 30 days. Wand checks current D1 ownership, grants and revocation on commands. Hosted Firebase session revocation can take up to ID-token expiry.

Device credentials are random 256-bit opaque tokens. The Mac stores credentials in Keychain; the relay stores token hashes. A leaked device token can impersonate the device and forge its results, but cannot authenticate as an owner to issue commands. Revoke and re-pair to replace it. A compromised authorized assistant account can exercise its granted capabilities; operator confirmations are a UX layer, not an independent security boundary.

Build 33 deliberately changed the Developer ID signing team to the owner's `58XWD3LBSS`. Existing Keychain and macOS privacy grants may refer to an older signing identity. On the tested installation, the owner's persistent Keychain approval and targeted repairs of Wand's stale Accessibility and Screen Recording entries restored access. After confirmed process exit and relaunch, Keychain access, text observation and real window capture persisted without another password prompt. The final same-team build 34 CI app subsequently reconnected without a permission prompt and passed first-request Safari/TextEdit capture plus independently verified text input. After a confirmed unchanged-app restart it reconnected without Keychain or privacy prompts and returned a fresh Safari image; disposable fixtures were removed. This is evidence for that installation, not a guarantee of migration on every Mac. Credentials were not exported or moved to files, and no blanket Keychain or privacy reset was used. Fresh-user setup and a full reboot remain separate checks.

## Transport and execution

The Mac initiates its outbound TLS WebSocket. No inbound network port is needed. The relay sees command contents; end-to-end payload encryption is not implemented. The reserved encrypted payload is rejected rather than treated as protected data.

Commands use a closed schema-validated catalog, 15-second relay timeout, expiry validation and bounded agent deduplication. There is no offline queue or reconnect replay. Lock, sleep and session changes invalidate desktop snapshots. A locked Mac returns only lock status and rejects actions except idempotent lock. Check fresh per-device capabilities before dispatch; unsupported or unavailable actions fail rather than being simulated. An allowlisted Shortcut may execute code; an absent shell endpoint is not a code-execution guarantee.

## Desktop control

The owner grants persistent desktop control locally and can pause it. Accessibility allows observation and input; screenshots additionally need Screen Recording. The consent covers apps across the Mac, including capable apps such as Terminal. GUI control can expose sensitive content, delete files, execute code or change settings. App contents are untrusted inputs, and no denylist is a complete sandbox. Protected password/security surfaces and Wand itself have additional exclusions. Confirm consequential actions, but do not rely on model instructions to contain a compromised caller.

A compromised relay can forge allowed commands and results. Agent-side validation, lock/session guards and local consent limit this risk but do not prove user intent. Independent step-up approval and end-to-end encryption remain roadmap work.

## Revocation and deletion

Local revoke requests server revocation before disconnecting when online. Offline or unacknowledged revoke leaves a persistent warning to finish through the dashboard. Account deletion revokes grants and device tokens, closes live device sockets, and purges active application records. An offline device learns revocation on reconnection. Already dispatched actions cannot be recalled. Hosted sign-in identity deletion and backup deletion replay are not promised.

## Data and forensics

Cloudflare D1 holds registry/consent data; per-device Durable Objects hold command/audit records. Cloud audit parameters are redacted. Transient state results expire after 60 seconds. The Mac's private local log keeps full validated parameters and outcomes with a 90-day/10-MiB bound. Therefore cloud logs cannot reconstruct which URL or Shortcut an attacker used; lost local logs cannot be recovered from redacted records.

Cloud command/audit retention is 90 days, then purge. Cleanup uses Durable Object alarms. Database administrators can alter records: append-only application writes do not make audits tamper-proof. Backup restoration requires a separate deletion-replay review. The support form sends messages through Cloudflare to a fixed support mailbox under the public privacy policy; messages do not enter command logs. A successful send response establishes provider acceptance, not confirmed inbox delivery.

A live support test sent September 24 at 07:23:42 UTC was independently confirmed in the operator's inbox with HTML and plain-text content. Gmail reported SPF, DKIM and DMARC passing. See [SUPPORT_FORM.md](../docs/SUPPORT_FORM.md#september-24-2026-live-delivery-check).

During an incident, revoke affected devices/connections, preserve local logs with owner consent, correlate command IDs/timestamps, and review authentication records. Re-pair only after containment. Never claim redacted cloud logs reconstruct content.

## Limits and review boundaries

Relay limits include 60 commands/minute/user, 10/second/device, 5 pairing attempts/minute/IP and limited WebSocket hello attempts. Limits use Cloudflare Durable Objects, not a process-local single-server assumption. Application authentication, ownership checks, schema validation and limits remain required even when public discovery is reachable by non-browser clients.

No remote-unlock, camera/microphone or direct arbitrary-shell action exists. Desktop GUI and allowlisted Shortcuts can nevertheless perform broad local work. Independent security review, native Muse connector testing and physical coverage beyond the recorded acceptance cases remain separate from automated test results. See [OPERATOR.md](../connector/OPERATOR.md) for device selection, capability checks, confirmation policy, polling and timeout handling, and [DESKTOP.md](../connector/DESKTOP.md) for the observe/act/verify loop.
