# Wand 0.9.2 — release preparation, September 20, 2026

## Shipped
- Public Google-only sign-in; Facebook button/linking hidden using the existing feature flag. Existing Firebase account links are preserved.
- Dashboard Terms and Support links; provider-neutral sign-in error messages.
- Public /developers page with actual API base, OpenAPI/discovery URLs, OAuth PKCE flow, limits, current actions and candid reviewer-access status.
- Privacy page operator/support contact, current sign-in description, and updated download page account status.
- Native startup no longer blocks the AppKit event loop on Keychain. Local UI and state reads initialize independently; cloud pairing and the authenticated localhost API wait for connection keys. Connect remains disabled until credentials are ready. Existing secrets are not deleted or moved to plaintext.
- Rebuilt and installed /Users/Shared/Wand.app (0.9.2/11), regenerated local-only dist/Wand.dmg. Ad-hoc signature verified; not notarized or published as a public download.

## Verified
- 29 Cloudflare tests passed. Fixed a test-helper race: hello already sets heartbeat freshness; an extra queued heartbeat was overwriting the manually expired timestamp in the offline test.
- 9 native tests passed including a real read-only state request; clean scratch build avoids Finder/resource-fork metadata in the workspace build directory.
- Dashboard onboarding checks and six website tests passed.
- Live config reports facebookEnabled=false. /developers returns 200.
- Updated native UI visibly reports real battery/application state while Keychain authorization remains pending. This does not prove a cloud action.

## External integration
The genuine Muse submission form at https://muse.ai/platform accepts an individual developer. A draft for Wand reached Review with OAuth PKCE, the live API/spec/docs and current limitations. It is NOT submitted: native cloud acceptance and a reviewer-ready device/public signed installer are still unavailable. No Muse client callback has been provisioned and MUSE_CLIENT_IDS remains empty.

## Still required
- User directly approves the macOS SecurityAgent Keychain prompt, then native pairing and a real remote action can be tested. Computer-use explicitly denies access to that app.
- Apple Developer ID identity and notarization. Live signing inventory has zero valid identities.
- Real Muse registration/review and phone-to-Mac test.
- Lock, sleep, pinned-tab preservation and Focus remain unimplemented OS-dependent actions, not shipped features.
- Previously exposed Facebook app secret still needs rotation before re-enabling public Facebook login.
