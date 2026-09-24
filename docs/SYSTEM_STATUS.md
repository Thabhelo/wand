# Mac status readings

`get_state` reports minimized information while the Mac is unlocked: frontmost app name, running app names, battery/charging, playback when available, current volume/mute state and an optional `system` object. Older agents may omit newer fields; use [capabilities](../contracts/CAPABILITIES.md) instead of guessing support.

The `system` object includes:

- Storage capacity and free bytes on the user's home volume; no external-volume inventory or reclaimable-space prediction.
- Physical memory and approximate in-use bytes from active, wired and compressor pages. This is not Activity Monitor's precise accounting or a memory-pressure measurement.
- Time since kernel boot, including sleep; clock changes can affect it.
- macOS version, Low Power Mode and thermal severity. These remain API fields. The dashboard omits them; the native status view currently still includes thermal severity.

The dashboard shows battery, storage, approximate memory, uptime, front app, playback and running apps. Low battery and low storage receive visible warnings. Music controls use actual volume/mute readings, and absent audio is shown as unavailable rather than a default value. Version/build identity appears separately beneath the selected Mac's name, using its capability report.

Readings require no extra status-specific permission. State is checked before and after collection; locked results contain only `screen_locked: true`. Missing readings are null, not zero. Payloads are transient and excluded from cloud audit contents. No serial number, hardware UUID, file names, URLs or window titles are part of `get_state`; separately permissioned desktop observation has broader access.

Implementation: `agent/Sources/MacBridgeNative/SystemStatus.swift`, `ActionExecutor.swift` and `web/dashboard.js`. Regression coverage includes `SystemStatusTests.swift`, shared schemas and `site/tests/dashboard-controls.test.mjs`. Current release evidence belongs in [BUILD_STATUS.md](BUILD_STATUS.md), not a build-specific copy of this feature guide.
