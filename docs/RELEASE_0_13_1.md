# Wand 0.13.1, build 34

Released September 24, 2026. [Download Wand](https://getwand.app/download/) for Apple silicon and macOS 26 or later.

## Changes

- Improved Safari cleanup to retain pinned tabs and corrected repeated-lock results.
- Raised and verified the selected window before observation. Capture now uses up to three bounded lookups with two pauses for the same window and geometry; changed identity aborts.
- Replaced the native volume slider’s fixed initial value with cached Mac audio state. Activation and completed audio actions refresh it without replacing command feedback. Rendering performs no audio read; unavailable state disables the slider and refresh leaves an active drag alone.
- Preserved bundle identifier `local.macbridge.agent` and Developer ID team `58XWD3LBSS` from build 33.

## Verified artifact and live results

Source `0d7960f` passed 54 Swift tests, release compilation and 50 website tests. [CI run 35975546500](https://github.com/Thabhelo/wand/actions/runs/35975546500) signed and notarized the release. App/DMG strict signatures, stapled tickets and Gatekeeper passed. The exact CI app was installed at the existing path with the unchanged designated requirement.

DMG SHA-256: `b0d2c1c060ce4f2a530bca7ff41d4aa16f4ba3db79e44b70dae0db358dccdf5f`.

Publication commit `59e4a6d` and Cloudflare deployment `a786688e-6676-4874-b085-2f87ee610a07` went live. The public download page, DMG hash and checksum manifest matched the verified artifact.

The first Safari and TextEdit image requests succeeded without manual window raising. Native accessibility inspection independently confirmed two lines entered through the relay. The native volume display matched the Mac’s reported `100`; this check did not change volume or exercise dragging.

After confirmed exit and relaunch, Wand reconnected without Keychain or privacy prompts. Its first Safari image after restart returned Example Domain and a complete 640 × 357 image. Disposable TextEdit fixtures were removed and file absence verified. [Desktop acceptance](DESKTOP_ACCEPTANCE.md#september-24-build-34-release-results) records command identifiers and distinguishes final-artifact results from earlier candidate tests.

Earlier build 34 candidate tests verified real relay lock/repeated-lock and local Safari pinned-tab cleanup. A physical sleep test verified about 43 seconds asleep followed by reconnect. The owner confirmed waking the Mac manually, consistent with the keyboard/UserActivity event in the power logs. Sleep and reconnect passed; the manual wake ended the test before the longer offline interval could be measured.

## Remaining coverage

Fresh-user or second-Mac installation, a full Mac reboot, and the live 75-second missed-heartbeat/offline interval remain unverified for this release. Native Muse client registration and OAuth/tool-image compatibility remain pending. Existing web-control tests do not establish native Muse integration.
