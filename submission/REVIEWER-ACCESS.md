# Review Wand

Updated September 24, 2026. Public Mac release: **0.13.0, build 33**.

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

The September 24 run passed status, mute, unapproved-Shortcut rejection, approved Shortcut execution, offline rejection, reconnect, repeated lock, minimal locked state, rejection of mute while locked, and revocation. An old-socket status race was found and a correction deployed; final retesting of that correction is pending.

## Physical Mac

Download https://getwand.app/download/. Build 33 is signed by Thabhelo Duve and notarized, for Apple silicon and macOS 26+. Install, open Wand, choose **Connect**, sign in with Google and approve your Mac. Use a test Mac with disposable documents/tabs. Updating from build 32 changes the signing identity, so macOS may request approval again. Enter passwords only in the macOS dialog; **Always Allow** remembers access to Wand's connection keys. Do not reset existing permissions as a routine installation step.

Use https://app.getwand.app/ for physical controls. Native desktop access requires local consent plus macOS Accessibility; screenshots also require Screen Recording. Neither the sandbox nor a support request grants access to the developer's Mac.

For a bounded desktop check:

1. In Wand on the Mac, enable desktop control and approve Accessibility for the installed app.
2. Open a new, disposable TextEdit document. In the web dashboard, choose that Mac and inspect its current capability/permission status.
3. Observe TextEdit, enter a harmless test phrase through Wand, then observe again and compare the returned text with the actual document. With Screen Recording approved, include a window image. Use a fresh observation after every action or expired snapshot. Input acknowledgement alone is not proof that the edit succeeded.
4. Quit and reopen Wand. Wait for automatic reconnection, then make a fresh observation of the same document and request another image if that permission is enabled.
5. Pause desktop control when finished and discard only the disposable test content.

Text observation, real window images, independently verified text input and scrolling, and unchanged-app restart persistence passed on the developer's build 33 installation on September 24. Keychain, Accessibility and Screen Recording survived that restart. Fresh-user setup, a full Mac reboot and a future same-team binary update remain separate checks. The full evidence and remaining coverage are in [PERMISSION_LIFECYCLE.md](../docs/PERMISSION_LIFECYCLE.md#september-24-owner-signing-build-33). Report setup problems through https://getwand.app/support/ without sending passwords, device tokens or connection codes.

Support-form delivery to the operator's inbox was independently confirmed on September 24, including HTML/plain-text content and passing SPF, DKIM and DMARC checks.

## Muse connection

The API and OAuth service are deployed. Meta's client and exact callback are not registered. Please provide verified callback/client requirements and the supported tool/image interface so Wand can provision the client and complete native Muse authorization and command-result testing. The owner confirms Muse has already controlled the Mac through Wand's web interface and supplied test feedback. That evidence does not establish native OAuth/direct-tool compatibility.
