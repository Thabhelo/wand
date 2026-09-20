# MacBridge submission draft — not submitted

## Product description
MacBridge connects an assistant to a user's own Mac through a small menu-bar agent. The intended journey is: install and pair the agent, enter its six-character code in the authenticated dashboard, then ask Muse on an iPhone to act on that Mac. For example, “Lock my MacBook” prompts confirmation, dispatches a lock request over the Mac's outbound connection, and reports the actual result. No separate iOS application is required. People who forget an open laptop or need a pre-approved desktop workflow while away are the initial audience.

The agent exposes a fixed action catalog, not general remote desktop access. Device selection, human-readable errors and honest offline handling are central. Windows, Linux and other device agents can later reuse the relay protocol. No claims of working phone-to-Mac control should be made before the deployment and platform integration are verified.

## Functional materials
- ../connector/openapi.json: implemented REST operations and shared schema definitions. Replace deployment and OAuth placeholders before submission.
- ../connector/manifest.json and OPERATOR.md: action metadata and assistant operating rules; Meta's exact import format remains unverified.
- ../tests/test_relay.py and ../harness/: executable test peers. They are not a reviewer-accessible hosted sandbox.
- ../agent/: real pairing and transport; OS actions remain guarded by unverified lock detection. Several OS capabilities are explicitly unsupported pending empirical verification.

Release/submission gates: hosted HTTPS relay and Auth0 client configured; dedicated standard-user Mac test session completes physical-action acceptance tests; notarized DMG; reviewer sandbox URL and credentials; recorded demo; confirmed Meta integration/auth format; privacy/terms reviewed. This packet is not submission-ready.

## Two-minute demo script
0:00 Show MacBridge menu and the web dashboard. Explain that this Mac is a disposable review device.
0:15 Generate a real pairing code; claim it in the dashboard; show online status.
0:35 On the phone ask Muse to lock the named Mac. Show fresh confirmation and actual lock screen. State that remote unlocking is impossible.
0:55 Unlock locally. Ask to close Safari tabs while retaining pinned tabs; show confirmation and the resulting tabs.
1:15 Ask to run a harmless allowlisted Shortcut. Show rejection for a different name, then the approved result.
1:35 Disconnect the device network; after heartbeat expiry show device_offline and last_seen, with no queued work.
1:50 Reconnect, revoke from dashboard, and show the agent unpaired. Show redacted relay audit versus full local forensic parameters.
Do not film simulations as proof of physical actions. Film after these behaviors are actually verified.

## Featured placement pitch
MacBridge is designed to bring the connector experience to a user's own physical computer: a clear phone-to-Mac demonstration with practical value, a narrow action catalog, no remote unlock, and honest visibility into offline devices. It extends assistant usefulness beyond cloud services while making the trust boundary understandable. We seek consideration as a physical-device connector; we have not established that it is the first.

## Platform evidence
Checked 2026-09-20: https://muse.ai/platform describes product description, functional/security/legal review, end-to-end testing and directory placement. It does not specify the complete OAuth or manifest import contract on that public page. OAuth2 authorization code through Auth0 is the implementation choice, not a verified Meta requirement. https://ai.meta.com/muse/ is the official product page.
