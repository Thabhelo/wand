# Wand 0.10 desktop-control beta — 2026-09-20

Muse owns planning; Wand exposes desktop_observe, desktop_act and desktop_stop through the authenticated relay. Native grants cover up to ten locally selected apps for 15 minutes. The installed app and downloadable DMG are ad-hoc signed, not notarized.

## Directly observed acceptance evidence
Using the deployed app.getwand.app/desktop page, Google-authenticated owner account and the paired physical Mac on macOS 26.6.2:
- Owner granted macOS Accessibility and a 15-minute TextEdit session locally.
- desktop_observe returned the real empty TextEdit window and accessible controls.
- desktop_act replaced document text with `Wand desktop test passed.` Text appeared in native TextEdit; a fresh relay observation returned it.
- AXPress on Bold succeeded; native TextEdit reported Bold enabled.
- desktop_stop succeeded. The next observation was rejected with desktop_permission_required; native Wand showed Desktop control is off.
- Only the disposable TextEdit document was targeted. TextEdit auto-saved it as Untitled.rtf; it was left for inspection.

The interactive test preceded a defensive patch that rechecks a grant after asynchronous activation, removes a force unwrap, and excludes Apple Passwords. The patched binary compiles; the earlier interactive run does not test these race cases.

## Automated validation
32 relay tests, 12 Swift tests, 18 Python contract tests, and 7 website tests pass. Coverage includes closed parameter validation, invalid observation results, protected apps, grant stop, missing snapshots, and existing OAuth grants not gaining desktop scopes.

## Remaining validation and integration
Optional window images, coordinate clicks, key injection, scrolling, multi-app switching, lock/sleep interruption and broad app compatibility are not live-verified. Input delivery is not task completion; callers must inspect again. Cloud audit redacts parameters; local logs retain full parameters including typed text.

Real Muse registration/callback and image/tool-loop compatibility remain unverified. No Muse submission receipt or approval is claimed. The working web test controls use the same relay tools but are not Muse. General autonomous desktop task completion is not release-proven.

Public beta: https://getwand.app/download
Test controls: https://app.getwand.app/desktop/
Operator contract: connector/DESKTOP.md
