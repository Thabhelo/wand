# Threat model and incident response

The relay sees command contents in transit. TLS protects hops, not the relay operator or a compromised relay. encrypted_payload is reserved and rejects non-null data: this is not implemented end-to-end encryption.

A hostile internet client cannot select another account's device through the REST ownership checks. Auth0 JWTs require RS256, issuer, audience, expiry, admitted OAuth client and control scope. A leaked device token can impersonate that device, receive its commands and forge its results. It cannot authenticate as the user to dispatch commands. Revoke the device immediately. Tokens are 256-bit random opaque values; the agent stores them in Keychain, the database stores SHA-256 hashes. Re-pairing after revocation generates a new token; seamless rotation is not implemented.

A compromised Muse account/admitted OAuth client can request any authorized catalog action. Confirmation instructions are a UX layer, not a security boundary. Rate limits and audit records aid containment/investigation but do not prevent individual harmful authorized actions. v2 must add out-of-band high-risk approval on an independent device, bound to user, client, device, action, parameter digest, nonce and expiry. AuthorizationContext reserves oauth_client_id and allowed_actions; new clients must receive explicit per-client scopes before admission. The current admitted dashboard/connector clients receive the full catalog.

A compromised relay can forge commands and results. The Mac still validates the closed catalog, expiry, deduplication, lock-state guard and local Shortcut allowlist. It cannot distinguish a newly minted malicious allowed command from a legitimate one in MVP. An allowlisted Shortcut may run code: arbitrary shell is excluded from direct actions, not prevented inside trusted Shortcut contents.

Local revocation marks pending before deleting the Keychain credential. Online revoke_self requests server revocation; offline or unacknowledged revocation shows a persistent warning directing the user to the dashboard. Account deletion revokes devices, sends revoke and closes active sockets with 4003, then purges application records. Disconnected devices learn of revocation on next connection. Hosted identity deletion and backup deletion replay are not implemented and must not be promised.

## Forensics split
Cloud command and audit parameters are redacted. The relay cannot answer which URL or Shortcut name was used. The Mac's private local log records full validated parameters before attempted execution and outcome afterward, with a 90-day/10-MiB cap. It is the forensic source for those details; lost or erased local logs make them unrecoverable. State payloads are transient relay memory for polling, expiring after 60 seconds. No token or state payload is written to the action logs.

During an incident, revoke affected devices and hosted sessions first, preserve the user's local command log with their consent, correlate command IDs and timestamps with cloud audit events, then review the hosted authentication records. Reinstall/re-pair only after containing the compromise. Do not imply a redacted cloud log can reconstruct content.

## Operational limits
User command limit: 60/minute; device: 10/second; pairing issuance/claim: 5/minute/IP; WebSocket hello: 10/minute/IP (successful attempts also count conservatively). Limiters are process-local and bounded. Use a single worker. Proxy client-address trust must be configured and verified before deploying rate limits behind a proxy.

Audit insertion is append-only through the repository interface; retention/deletion purge is deliberate. SQLite administrators can alter data, so this is not tamper-proof evidence. Records expire at 90 days; this implementation purges rather than retaining aggregate personal records. Erasure removes active application data. Review storage-provider backups separately.

Never supported: remote unlock, arbitrary shell endpoint, synthetic keystrokes, file deletion, screenshots, camera/microphone. No incoming network port on the Mac is required for the relay connection. OS action verification, hardened local API, hosted deployment and external security review remain release requirements.
