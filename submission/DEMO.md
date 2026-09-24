# Wand review demo outline

Updated September 24, 2026. **This is an outline, not a recording or a completed native Muse demo.**

## Record the working web-to-Mac flow

Use Wand 0.13.0, build 33, a connected Mac you control, and a new disposable TextEdit document. Complete sign-in and macOS approvals before recording; keep passwords, connection codes, private documents and unrelated windows out of view. Dispatch the demonstrated actions through Wand, then independently show their effects on the Mac.

| Time | Show | Accurate narration |
|---|---|---|
| 0:00–0:15 | Installed Wand version and its connected Mac in the web dashboard | “This is Wand's current Mac beta. Native Muse connector registration is pending; this demonstration uses Wand's web controls and production relay.” |
| 0:15–0:30 | Read the Mac's current status and desktop capability state | Explain that available actions depend on the selected Mac, local consent and current permissions. |
| 0:30–1:00 | Observe the disposable TextEdit document with a window image, enter a harmless phrase, then observe again | Show the returned text/image and actual document. Explain that an input acknowledgement alone does not establish the intended result. |
| 1:00–1:30 | Quit/reopen Wand, wait for automatic reconnection, then observe and capture the same document again | Report only what happens in this recording. The developer's unchanged build 33 retained Keychain, Accessibility and Screen Recording access through this sequence on September 24. |
| 1:30–1:45 | Show the download, reviewer sandbox and support links | “Reviewers can use their own Mac or the explicitly simulated browser sandbox. Native Muse OAuth and tool/image compatibility are the next integration step.” |

After recording, pause desktop control and discard only the disposable document. Close the test tab and remove task-only recording intermediates while retaining the final recording. Watch the exported video before linking it in a form. Do not provide a demo URL until the actual recording is available.

## Optional separate segments

- A browser-sandbox segment may show offline rejection, unapproved-Shortcut rejection, simulated lock behavior and revocation. Label it **simulated device** throughout; it proves the hosted flow, not physical macOS execution.
- A real TextEdit image and image capture after app restart passed on the developer's current signing identity. The recording must still show its actual returned image; keep unrelated content outside the captured window.
- Add physical lock, sleep, browser cleanup or Shortcut execution only after that exact demonstrated path passes and the owner is available to recover the Mac. Historical local-action results are not a new production-relay result.

## Native Muse demo after registration

Once Meta supplies verified callback/client details, record the actual Muse authorization, device/action consent, capability discovery, a harmless command, its polled result, and the independently observed effect. Test image rendering if that interface is supported. Include revocation and failure handling as a separately identified tested segment. Never substitute this outline, the web-control recording or a marketing animation for evidence that the native connector works.
