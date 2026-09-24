# Installed app picker

The Mac app and web controls select discovered apps by bundle identifier. The dashboard uses one dropdown, ordered by available last-opened metadata; manual entry appears only after choosing **Other…**. Apps with the same name show their identifiers, and copies with the same identifier are deduplicated.

`list_apps` is read-only on an unlocked Mac. It returns up to 100 entries per page and `next_offset`, without file paths. Discovery combines Spotlight, common installation folders and running applications. Nested helpers, background-only apps and protected session components are excluded. The agent also checks protected targets when opening or closing an app; a manual name is not a bypass.

Discovery runs off the UI thread. Results are cached for 30 seconds; the first page refreshes the inventory. Ordering uses Spotlight last-used dates and running-process launch dates; unknown dates sort alphabetically. This is best-effort recency, not a complete history or a guarantee that every installed app is discoverable. **Other…** remains necessary for unindexed or inaccessible installations.

The relay validates the bounded result and retains it only transiently. The browser keeps the inventory in memory, clears it on device changes and ignores late responses from a different Mac. Lock state is checked before and after collection. Existing OAuth grants do not automatically gain `list_apps`.

Implementation: `agent/Sources/MacBridgeNative/AppInventory.swift`, `AppTargetPolicy.swift`, and `web/app-picker.js`. Regression coverage: `AppInventoryTests.swift`, `site/tests/app-picker.test.mjs` and `site/tests/control-feedback.test.mjs`. See [current status](BUILD_STATUS.md) for the released build, rather than historical app counts or installer links.
