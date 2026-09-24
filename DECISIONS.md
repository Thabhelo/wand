# Architecture decisions

Current decisions, reviewed September 24, 2026. Superseded phase plans and blocker snapshots are in Git history. See [current status](docs/BUILD_STATUS.md) for release readiness.

| Date | Decision | Reason |
| --- | --- | --- |
| September 20 | JSON Schema and a closed action catalog shared across components. | Keep command names, validation and results consistent. |
| September 20 | Production uses Cloudflare Workers, D1 and one SQLite Durable Object per device. Python/FastAPI remains a reference implementation. | Route outbound device sockets without a single-process production registry. |
| September 20 | Firebase Google sign-in identifies users; separate Wand OAuth consent authorizes assistants for selected devices/actions. | Signing in does not grant an assistant control. Auth0 is not used in production. |
| September 20 | Pairing separates unauthenticated code issuance, authenticated owner claim and bootstrap-authorized redemption. The Mac creates and stores the durable token in Keychain; the relay stores hashes. | A short pairing code cannot authorize commands or replace durable device credentials. |
| September 20 | Outbound WSS only; a bearer-protected loopback HTTP API serves future local integrations. No silent offline queue or replay on reconnect. | Avoid inbound network ports and delayed surprise actions. |
| September 20 | Expiry, bounded deduplication and connection-generation checks apply before execution. Revocation stops commands and invalidates credentials. | Reject stale, duplicate and revoked requests. |
| September 20 | Locked Macs expose only locked status and acknowledge repeated lock requests. Unknown lock state fails closed. | Minimize disclosure and avoid acting in another user's session. |
| September 20 | Desktop control uses persistent local consent plus macOS permissions, not a separate Wand LLM. | Muse chooses the work; Wand validates and executes bounded tools. This supersedes the original exclusion of window images and typing. |
| September 20 | Remote unlock is research only and absent from the action catalog. No dedicated arbitrary-shell endpoint. | No supported unlock implementation has been verified. Desktop access and approved Shortcuts can still execute code; do not claim otherwise. |
| September 20 | Relay audits redact parameters; full command parameters stay in the Mac's local log. Result payloads are transient. | Balance investigation on the owner's machine with cloud data minimization. |
| September 20 | Conversational confirmations are operator behavior, not proof of independent user approval. | Document the actual trust boundary. Out-of-band step-up approval and end-to-end payload encryption remain roadmap work. |
| September 23 | Submit Raw API + OpenAPI with OAuth/PKCE. MCP is an optional future adapter over the same relay. | The observed form supports Raw API; unverified MCP claims do not justify replacing the backend. |
| September 23 | Use versioned per-device capabilities with separate implementation support, OAuth authority and current availability. | Do not guess features from versions or signatures. Changed reports travel over the existing socket; consumers read the relay's no-store endpoint. |
| September 24 | Public releases use the owner's Developer ID team and GitHub signing/notarization workflow. Preserve identity across future updates. | Remove reliance on another developer's credentials and avoid avoidable permission migrations. |
| September 24 | One current status page; keep only useful current runbooks and bounded acceptance evidence. | Old phase/release checklists had been mistaken for current blockers. |

See [transport](contracts/TRANSPORT.md), [capabilities](contracts/CAPABILITIES.md) and [security](submission/SECURITY.md) for detailed guarantees and limits. No general-app compatibility, Muse approval or native integration is implied by implementation alone.
