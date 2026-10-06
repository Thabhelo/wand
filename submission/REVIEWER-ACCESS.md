# Review Wand

Updated October 5, 2026. Public Mac release: **0.13.1, build 34**, signed and notarized. The owner confirms the Muse connector application has been submitted and is awaiting review.

## Browser sandbox

Open https://app.getwand.app/review/ and sign in with your own Google account. No shared password or developer account is needed. Choose **Create test Mac**. The device exists only for your account; its credential stays in page memory.

1. Send **Check Mac status**; expect `succeeded` with synthetic state.
2. Send **Mute the Mac**; expect success with no physical effect.
3. Try an unapproved Shortcut; expect `action_not_allowlisted`. `Review Demo` is the approved synthetic Shortcut.
4. Choose **Take offline** and send a command; expect `device_offline` with `last_seen`. Reconnect.
5. Lock the simulated Mac. Status returns only `screen_locked: true`; locking again succeeds with `already_locked: true`. Other actions fail while locked.
6. Choose **Revoke test Mac** when done. Create a new one to restart.

Closing the tab disconnects the simulated device. Remove any leftover device through https://app.getwand.app/. Records follow the privacy policy; account deletion removes application records.

This tests hosted authentication, pairing, device ownership, outbound WebSocket routing, results, offline handling and revocation. It does not prove macOS execution or Muse integration.

The September 24 run passed status, mute, unapproved-Shortcut rejection, approved Shortcut execution, offline rejection, reconnect, repeated lock, minimal locked state, rejection of mute while locked, and revocation. An old-socket status race was corrected and deployed. After reconnect and several minutes, status commands succeeded while the page remained online. All task-created review devices were revoked; the page confirmed final revocation and hid the device controls.

## Physical Mac

Download https://getwand.app/download/. Build 34 is signed by Thabhelo Duve and notarized, for Apple silicon and macOS 26+. Install, open Wand, choose **Connect**, sign in and approve your Mac. Use a test Mac with disposable documents/tabs. Updating from build 32 changes the signing identity, so macOS may request approval again. Enter passwords only in the macOS dialog; **Always Allow** remembers access to Wand's connection keys. Do not reset existing permissions as a routine installation step.

Use https://app.getwand.app/ for physical controls. Native desktop access requires local consent plus macOS Accessibility; screenshots also require Screen Recording. Neither the sandbox nor a support request grants access to the developer's Mac.

For a bounded desktop check:

1. In Wand on the Mac, enable desktop control and approve Accessibility for the installed app.
2. Open a new, disposable TextEdit document. In the web dashboard, choose that Mac and inspect its current capability/permission status.
3. Observe TextEdit, enter a harmless test phrase through Wand, then observe again and compare the returned text with the actual document. With Screen Recording approved, include a window image. Use a fresh observation after every action or expired snapshot. Input acknowledgement alone is not proof that the edit succeeded.
4. Quit and reopen Wand. Wait for automatic reconnection, then make a fresh observation of the same document and request another image if that permission is enabled.
5. Pause desktop control when finished and discard only the disposable test content.

Text observation, real window images, independently verified input and scrolling, and unchanged-app restart persistence passed on the developer's build 33 installation on September 24. Keychain, Accessibility and Screen Recording survived that restart; its disposable TextEdit fixture was deleted and absence verified. Build 33 Focus on/off also passed independent verification. Build 34 candidate tests passed real relay lock/repeated-lock and local pinned-Safari cleanup.

The final build 34 CI app was verified and installed with the same signing requirement, then reconnected without a permission prompt. Its first Safari and TextEdit image requests passed without manual window raising, and native inspection confirmed two relay-entered TextEdit lines. Native volume correctly displayed `100` without changing it. After confirmed exit/relaunch, it reconnected without Keychain or privacy prompts and returned a complete Safari image on the first request. The disposable TextEdit fixtures were removed and file absence verified.

Fresh-user or second-Mac setup and a full Mac reboot remain open. A second sleep test verified about 43 seconds asleep and subsequent reconnect with normal unlocked state. The owner confirmed waking the Mac manually before the 75-second missed-heartbeat threshold, so the longer live offline interval and recovery from it remain unverified. The full evidence and remaining coverage are in [PERMISSION_LIFECYCLE.md](../docs/PERMISSION_LIFECYCLE.md#september-24-same-team-build-34) and [DESKTOP_ACCEPTANCE.md](../docs/DESKTOP_ACCEPTANCE.md#september-24-build-34-release-results). Report setup problems through https://getwand.app/support/ without sending passwords, device tokens or connection codes.

Support-form delivery to the operator's inbox was independently confirmed on September 24, including HTML/plain-text content and passing SPF, DKIM and DMARC checks.

## Muse connection

The submitted application uses Raw API + OpenAPI. The API and OAuth service are deployed. A public PKCE client (`kqQLjzgKBLLzJ7Ff`, no secret, S256, no dynamic registration) is registered with the callback `https://agent.meta.ai/api/hatch/oauth/callback`. On October 5 Muse authorized through that client with that callback and the resource `https://api.getwand.app/connector`, from the owner's Muse account. If Meta's review uses a different callback, report it through https://getwand.app/support/ and it will be registered.

A dedicated reviewer account, `reviewer@getwand.app`, is supplied through the credentials form. To use it: install Wand from https://getwand.app/download/ on your own Apple-silicon Mac (macOS 26+), open Wand and choose **Connect**, then on the page that opens choose **Use email instead**, enter the reviewer email and password, choose **Sign in**, and approve your Mac. Grant Accessibility and Screen Recording only if you want to test desktop actions. The account owns no devices and has no access to the developer's Mac. Disconnect your Mac from the dashboard when finished. Muse first controlled the Mac through Wand's web interface, and since October 5 through the native connection. The owner's session reports passing native tests of status, audio, apps, URLs and desktop observation and input; [the record](../docs/FIREBASE_CONNECTIONS.md#native-muse-connection-october-5) separates what production records show from what was reported.

## Native action evidence

The October 5 custom Muse connector tests include independently verified audio/app actions and TextEdit images, clicking, typing and scrolling. [Command IDs, cleanup and limits](../docs/NATIVE_MUSE_ACCEPTANCE.md) distinguish these from subsequent owner-verified passes. No reviewer access to the owner’s Mac is granted.
