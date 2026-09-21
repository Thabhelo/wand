# Mac health snapshot — build 30

`get_state` now includes an optional `system` object on unlocked devices. It is optional so older agents and clients continue to work. Both the web dashboard and native window display the new information.

- Storage: available and total bytes on the user's home volume. This is currently free capacity, not a prediction of space macOS could reclaim by purging caches. Other volumes are not enumerated.
- Memory: physical capacity and approximate in-use bytes, computed from active, wired and compressor pages. This is not Activity Monitor's precise app-memory accounting, a memory-pressure measure, or proof that an app needs quitting. Clamp counters to physical capacity and handle overflow.
- macOS: version only; no serial number, hardware UUID or build fingerprint.
- Since restart: elapsed wall-clock seconds since the kernel boot time, including sleep; null if unavailable. Clock changes can affect this value.
- Low Power Mode: the system's current setting.
- Thermal condition: macOS's reported severity, presented as normal/warm/hot/critical; not a temperature sensor reading.

No polling loop or extra OS permission is added. Readings are collected when status is requested, with lock state checked before and after execution. Locked results still contain only `screen_locked: true`. Missing readings are null and shown as unavailable; a real zero is not treated as missing. Results remain transient in the existing relay result cache and are not placed in cloud audit logs. No files, addresses, identifiers or per-process resource data are collected.

Verification: 21 native tests, 33 Cloudflare tests, 11 website tests, dashboard onboarding and extended-status tests; Python suite 46 tests, 5 existing skips. Coverage includes optional fields for older agents, rejecting system details on locked results, rejecting extra identifiers, zero-value display and clearing old details on lock.

Apple references: https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacity and https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property . Any future App Store distribution must review required-reason API declarations for storage and boot-time APIs against Apple's then-current permitted usage; this release remains a direct-download development-signed beta.

Live acceptance: production dashboard `get_state` returned and displayed all six new fields from the installed build 30, with no new permission prompts. The signed DMG binary matches the installed binary and passes strict signature and image-integrity checks. Relay deployment: `29986b2e-66cd-4dfd-9e46-1746aea054c6`. Website deployment: `c5d4c6e3-e905-4640-98fe-8294cd4558e2`.

Build 31 simplifies the visible status: macOS version and Low Power Mode remain available in the API but are omitted from the Mac app and dashboard. Native readings use aligned label/value rows; the dashboard uses responsive cards.
