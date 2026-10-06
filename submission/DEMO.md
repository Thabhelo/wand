# Wand review demo outline

Updated September 24, 2026. The Muse application is submitted and awaiting review, per the owner. **This is a recording outline, not a completed native Muse demo.** Web-to-Mac use has been tested, and a native connection from the owner's Muse account has worked since October 5 ([record](../docs/FIREBASE_CONNECTIONS.md#native-muse-connection-october-5)); no native demo has been recorded.

## Record the working web-to-Mac flow

Use the published Wand version shown on the download page, a connected Mac you control, and a new disposable TextEdit document. Show the exact installed version in the recording. Complete sign-in and macOS approvals before recording; keep passwords, connection codes, private documents and unrelated windows out of view. Dispatch the demonstrated actions through Wand, then independently show their effects on the Mac.

| Time | Show | Accurate narration |
|---|---|---|
| 0:00–0:15 | Installed Wand version and its connected Mac in the web dashboard | “This is Wand's current Mac beta. This demonstration uses Wand's web controls and production relay, not the native Muse connection.” |
| 0:15–0:30 | Read the Mac's current status and desktop capability state | Explain that available actions depend on the selected Mac, local consent and current permissions. |
| 0:30–1:00 | Observe the disposable TextEdit document with a window image, enter a harmless phrase, then observe again | Show the returned text/image and actual document. Explain that an input acknowledgement alone does not establish the intended result. |
| 1:00–1:30 | Quit/reopen Wand, wait for automatic reconnection, then observe and capture the same document again | Report only what happens in this recording. The developer's final build 34 retained Keychain, Accessibility and Screen Recording access through this sequence on September 24. |
| 1:30–1:45 | Show the download, reviewer sandbox and support links | “Reviewers can use their own Mac or the explicitly simulated browser sandbox. A recorded native Muse demonstration is the next step.” |

After recording, pause desktop control and discard only the disposable document. Close the test tab and remove task-only recording intermediates while retaining the final recording. Watch the exported video before linking it in a form. Do not provide a demo URL until the actual recording is available.

## Optional separate segments

- A browser-sandbox segment may show offline rejection, unapproved-Shortcut rejection, simulated lock behavior and revocation. Label it **simulated device** throughout; it proves the hosted flow, not physical macOS execution.
- A real TextEdit image and image capture after app restart passed on the developer's current signing identity. The recording must still show its actual returned image; keep unrelated content outside the captured window.
- Add physical lock, sleep, browser cleanup or Shortcut execution only after that exact demonstrated path passes and the owner is available to recover the Mac. Historical local-action results are not a new production-relay result.
- The final build 34 CI app passed first-request Safari/TextEdit capture without manual window raising, independently verified text input, and the native volume-display check. A confirmed unchanged-app restart reconnected without Keychain or privacy prompts and returned a first-request Safari image; disposable fixtures were removed and absence verified. Candidate lock/repeated-lock tests traversed the relay; pinned-Safari cleanup was a local native test. A second sleep test verified about 43 seconds asleep and reconnect after the owner manually woke the Mac. That manual wake ended the test before the 75-second missed-heartbeat/offline interval could be measured. Report those distinct outcomes accurately if demonstrating these actions.

## Native Muse demo

The native connection now works, so record the actual Muse authorization, device/action consent, capability discovery, a harmless command, its polled result, and the independently observed effect. Test image rendering if that interface is supported. Include revocation and failure handling as a separately identified tested segment. Never substitute this outline, the web-control recording or a marketing animation for evidence that the native connector works.
