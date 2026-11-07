# Wand 0.13.2

Unreleased. Build number to be set by the Mac release workflow input; the published build is [0.13.1, build 34](RELEASE_0_13_1.md). Apple silicon and macOS 26 or later.

## Why

On the owner's Mac, Wand was not running for at least 13 days after a reboot even though its login item was registered and pointed at `~/Applications/Wand.app`. A login item only starts the app at login. If Wand quits or crashes afterwards, nothing restarts it, and the Mac stays unreachable from the phone until someone walks to it. For a product whose promise is remote reach, the app has to come back by itself.

## Changes

- Replaced the plain login item (`SMAppService.mainApp`) with a keep-alive LaunchAgent bundled at `Contents/Library/LaunchAgents/local.macbridge.agent.keepalive.plist` and registered through `SMAppService.agent(plistName:)`. launchd starts Wand at login (`RunAtLoad`) and restarts it whenever it exits (`KeepAlive` true). `AssociatedBundleIdentifiers` keeps the entry under Wand's name in System Settings → General → Login Items.
- `KeepAlive` is unconditional rather than `{SuccessfulExit: false}`: a crash, a force-kill, an accidental quit and an explicit **Quit Wand** from the menu all bring Wand back while the startup setting is on. The way to keep Wand closed is to turn the startup setting off in Wand or in System Settings; Wand never re-registers itself after that.
- Existing users are migrated once, on the first launch of this build. A login item that was on is unregistered and replaced by the agent; a login item the user had turned off in System Settings is unregistered and not replaced; a setting the user had turned off in Wand stays off. New installs register the agent on first launch as before, one attempt only.
- One Wand per session. A copy started by hand while the launchd copy runs asks the running copy to show its window and exits. The launchd copy, started while a hand-opened copy runs (for example right after the migration), asks that copy to quit and takes over, because launchd would otherwise restart it every ten seconds. Turning the startup setting off from the launchd copy first hands the session to a plain copy, so the toggle does not close Wand.
- Renamed the checkbox to "Start Wand when I log in and keep it running" and updated its status lines.
- Marketing version 0.13.2. Bundle identifier `local.macbridge.agent` and Developer ID team `58XWD3LBSS` are unchanged, so users updating in place keep their Keychain, Accessibility and Screen Recording approvals. See the [permission lifecycle](PERMISSION_LIFECYCLE.md).

## Verified before release

Source checks on the owner's Mac: `make swift-check` passed; the app target compiled with Swift 6; `scripts/package_agent.py` produced a bundle whose `Contents/Library/LaunchAgents` holds the plist (sealed by the code signature), `plutil -lint` passed, and Info.plist reports `0.13.2`. `agent/Tests/MacBridgeNativeTests/StartupPolicyTests.swift` covers the migration decision, the double-start decision, the status messages and the bundled plist; it runs in CI (`swift test`), since this Mac's command line tools have no XCTest.

The double-start guard was exercised against the running 0.13.1: a self-contained copy of this build executed directly beside it exited 0 in 0.2 seconds, and with `MACBRIDGE_HANDOFF_FROM_PID` pointing at the running copy it waited 10.3 seconds and then stepped aside. The installed process kept its pid throughout. The take-over path (launchd copy replacing a hand-opened copy) was not run locally because it would have quit the installed app.

Nothing was registered on the owner's Mac. The installed 0.13.1 keeps running from `~/Applications/Wand.app` until the released build is installed.

## Test after installing the released build

Install over the existing `~/Applications/Wand.app` and open Wand once by hand. Record build, path and results without screenshots of password dialogs.

1. **Migration.** After the first launch, System Settings → General → Login Items shows one Wand entry, on. `launchctl print gui/$(id -u)/local.macbridge.agent.keepalive` lists the job. The hand-opened copy is replaced by the launchd copy within about ten seconds; only one `MacBridge` process remains (`pgrep -fl MacOS/MacBridge`). The phone still reaches the Mac without a new Keychain or privacy prompt.
2. **Quit from the menu.** Choose Quit Wand. Wand returns to the menu bar within about ten seconds and reconnects.
3. **Force-kill.** `pkill -9 -f MacOS/MacBridge`. Wand returns within about ten seconds and reconnects.
4. **Reboot.** Restart the Mac and log in. Wand is in the menu bar and reachable from the phone without opening it. Then leave the Mac alone for a day and check reach from the phone again; this is the case that failed before.
5. **Toggle off in Wand.** Untick the startup checkbox. Wand stays open; the Login Items entry disappears; `launchctl print` no longer lists the job. Quit Wand: it stays closed. Reopen it by hand: it does not re-register itself and the checkbox stays off.
6. **Toggle off in System Settings.** Turn the setting back on in Wand, then turn Wand off in Login Items. Wand's status line reads "Allow Wand in System Settings…", Wand does not re-enable itself after a relaunch, and the toggle in Wand still turns it back on.
7. **Second copy.** With Wand running, run `~/Applications/Wand.app/Contents/MacOS/MacBridge` from Terminal. It exits within a second and the running copy shows its window.

Only a real install proves items 1 to 7. In particular, whether unregistering the agent stops the running launchd copy, and so whether the hand-off in step 5 is needed, is launchd behaviour this change handles both ways but could not observe locally.

Update behaviour checked on the owner's Mac on 7 November 2026 with build 35: after the bundle was replaced, the old login item reported `notFound`, so build 36 treats `notFound` as "startup was on" and registers the keep-alive agent during the one-time migration; the off-state text no longer tells users in either Applications folder to move the app. Quit relaunched the app in 3 seconds and a force kill in 9.
