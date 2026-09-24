# Per-device capabilities

Owners call `GET /v1/devices/{device_id}/capabilities`. OAuth connectors use the
same path under `https://api.getwand.app/connector`. Other users' devices and
Macs outside the caller's consent return 404. Limit: 120 reads/minute/user.

## Interpret the document

- `contract_version: 1`: bump only for breaking changes. Ignore unknown fields,
  action names and features. Additions do not require a version bump.
- `revision`: device-report revision. Changes when report contents change, not
  on an identical heartbeat. It is not an authorization or freshness token.
- `agent_version`, `agent_build`, `os_version`: agent-reported metadata, or null.
  Never infer support from a version or signature. Signing is not attested here.
- `actions`: the existing catalog names, each with `support`, `authorized`,
  `availability`, `reason`, and `required_permissions`. No second action vocabulary.
- `features`: implementation support for individual result features. The additive
  `feature_status` map supplies their authorization and availability separately.
- `permissions`: last observed desktop consent, Accessibility and Screen Recording.
- `source`, `reported_at`, `stale`: where the report came from, relay receipt time,
  and whether it can describe the current connection. Offline or reports older
  than 75 seconds are stale; their permissions are returned as unknown.

`support` is `supported`, `unsupported`, or `unknown`. `authorized` describes only
this caller's OAuth scope; it does not grant local access. `availability` is
`available`, `blocked`, or `unknown`. Available means no reported precondition
blocks the action; it does not promise successful execution. Apps, target-specific
Automation permission, Shortcut allowlists and the current OS state are still
checked when executing. Confirmations remain an operator UX rule.

For example, locally disabled desktop access stays `support: supported`, with
`availability: blocked` and `reason: disabled_by_user`. Missing Screen Recording
blocks `desktop_images`, not text-only observation. Lock requires Accessibility
when unlocked; already-locked `lock_screen` remains idempotent. A locked Mac's
status reports only that it is locked; richer status features are unavailable.

## Reasons

| Reason | What the caller should do |
| --- | --- |
| `unsupported_build` | Explain that this build does not implement it. Offer an update only if one is available. |
| `not_authorized` | Ask the user to approve this action in the connector connection. |
| `disabled_by_user` | Explain how to enable desktop control in Wand. |
| `permission_denied` | Use `required_permissions` and `permissions` to identify the missing macOS permission. |
| `permission_unknown` | Explain that Wand cannot confirm permission yet. |
| `capability_unreported` | Say support is unknown; do not guess from build metadata. |
| `stale_report` | Re-fetch after reconnection or a fresh report. |
| `device_offline` | Report last-seen time from the device list; never queue work. |
| `device_locked` | Ask the user to unlock locally if they want to continue. |
| `session_unavailable` | Ask the user to return to their active Mac session. |

A null reason accompanies `available`. Runtime failures are command results, not
invented capability changes. Only a command result of `succeeded` confirms success.

## Updates and caching

The agent sends a complete report in `hello` and at most 25 seconds apart in
heartbeats. A non-prompting, two-second local check pushes a changed report early
on the existing socket. This covers local consent, permission and session changes.
The relay replaces its stored report immediately and increments its revision.
Unchanged reports refresh freshness without changing revision. Old socket
generations cannot overwrite a new connection's report. A legacy reconnect clears
old capability claims. Device/account deletion purges the report.

HTTP responses are `Cache-Control: no-store`: consumers re-fetch before planning
or acting. There is no downstream SSE/subscription API. Device-to-relay push
invalidates the relay's snapshot; it does not magically invalidate third-party
client caches. Dashboard refresh and pre-action fetches read that same document.
Do not cache solely by revision: offline state and OAuth consent can change without
changing a device report. No additional cron job, paid service or database is used.

The executable command catalog remains closed. Response clients tolerate additive
fields, while adding a device-advertised action requires deploying the relay's
validation schema first. An advertisement can never authorize arbitrary execution.

## Current availability

Capability reporting is deployed in the relay, dashboard and signed, notarized
Mac release; see [current status](../docs/BUILD_STATUS.md). It advertises the catalog actions and
the `audio_output_state`, `playback_state`, `app_inventory`, `desktop_images` and
`system_status` features. Read the document for the selected device; a released
feature can still be unavailable because of permissions, consent or device state.

Build 32 and other agents without a report return unknown support. The dashboard
fails closed for unknown actions, except basic status discovery and the desktop
Stop safety control. Offer the current update rather than guessing. The low-level
command API retains legacy behavior and validates commands on the Mac; capability
planning does not replace enforcement.

Raw API + OpenAPI is the connector interface. Native registration and review
progress are tracked in [current status](../docs/BUILD_STATUS.md); an MCP adapter
is optional future work over the same authorization path.
