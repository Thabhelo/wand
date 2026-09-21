# Installed app picker — build 29

The Mac app and web controls now choose installed apps by bundle identifier instead of requiring a guessed name. The web controls also filter by name or identifier. Other accepts a manual name or bundle identifier; duplicate names display their identifiers.

`list_apps` is a low-risk, read-only catalog action on an unlocked Mac. It returns up to 100 entries per page and `next_offset`, with no file paths. The device discovers apps from Spotlight, common installation folders and running applications, excluding nested bundle helpers and background-only apps. Copies sharing an identifier are deduplicated. Discovery runs off the UI thread; recent results are cached for 30 seconds, with first-page/explicit refresh rescanning. Missing/unindexed/inaccessible apps remain possible: manual entry is intentional.

Order uses available Spotlight last-used dates and running process launch dates, newest first. Unknown dates follow in alphabetical order. This is best-effort recency, not a complete usage history. Apple documents the metadata behavior at https://developer.apple.com/documentation/coreservices/kmditemlastuseddate .

Both relay implementations validate the new bounded response. Cloud results remain transient and inventory contents are excluded from audit records. The browser retains the list only in memory and discards an old device's late response after selection changes. Locked state is checked before and after discovery. Existing OAuth grants do not silently gain `list_apps`; clients must request that action within their permitted scope.

Verification: 19 Swift tests (sorting, locked-state rejection, unique identifiers, payload budget and no paths); 33 Cloudflare tests (including real fake-device protocol flow and account isolation for inventory); 11 website tests (pagination, filtering, duplicate labels, manual fallback, device-change race, offline/error behavior and text-only rendering). Contract tests and existing dashboard onboarding tests also pass.

Live: the production relay returned 320 apps from the owner's Mac. Filtering for TextEdit selected its bundle identifier and the Open app action succeeded. Build 29 retains the existing signing identity and its packaged binary matches the installed binary. No additional macOS access permission was requested for app discovery.

Release verification: the main web dashboard and desktop page each loaded 320 apps (322 choices including their placeholder and Other). A live TextEdit launch was confirmed by the foreground bundle ID `com.apple.TextEdit`. Public build 29 DMG SHA256: `c9e6d2fcbe9f2dbff9d3beab4cb88b37d319ce5ac193d2c5a8f403b4d23b7801`. Downloaded bytes match the local verified DMG. Relay deployment: `8fe37663-27bd-4c4a-9a79-9f76eb08d46b`; website deployment: `46ec6213-61e8-460f-942a-dbb4904b280e`.

The broader Python suite completed in a fresh temporary environment: 45 tests run, 5 existing environment-dependent skips, no failures. Existing dashboard onboarding/session-recovery checks passed. The original local virtual environment stalled while loading a dependency, so it was not used as release evidence.
