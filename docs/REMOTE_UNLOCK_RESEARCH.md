# Remote unlock feasibility — 2026-09-20

The owner now wants remote unlock investigated as a future feature, with explicit user permission. This supersedes the original permanent product exclusion, but does not add an executable action to the current contract.

## Findings

No documented internet-triggered session-unlock API suitable for Wand was verified in this investigation. This is a research limit, not proof that every implementation is impossible.

- Apple Auto Unlock with Apple Watch uses a nearby authenticated companion; it does not establish a supported phone-to-cloud-to-Mac unlock route. https://support.apple.com/en-gb/guide/security/sec6ab47ebfc/web
- LocalAuthentication authenticates the person to an app. A successful evaluation is not evidence that the macOS login session was unlocked. https://developer.apple.com/documentation/LocalAuthentication/LAPolicy/deviceOwnerAuthentication
- MDM Unlock User Account clears an account lockout; do not confuse this with unlocking the screen, FileVault at boot, or Activation Lock. https://developer.apple.com/documentation/devicemanagement/unlock-user-account-command

## Implementation gate

Identify and empirically verify an Apple-supported session authentication integration on the supported OS versions, including sleep/wake, account switching, and credential revocation. Investigate documented login authorization extensions and their deployment requirements next; they are not validated by this review.

Any design needs local opt-in on the target Mac, separate unlock permission, fresh approval on an independently authenticated owner device, device-bound signed single-use requests with short expiry, immediate revocation and audit records. Muse conversation confirmation alone is insufficient for this design. Show that unlocking makes the physical desktop accessible to anyone at that Mac.

Do not store a Mac login password in the relay, type passwords into the lock screen, disable the lock, or report an authentication callback as successful session unlock. FileVault preboot and Activation Lock are separate mechanisms and outside this investigation. Existing lock-state enforcement remains active until a reviewed implementation replaces it.

Status: research candidate; no unlock endpoint or working unlock feature shipped.
