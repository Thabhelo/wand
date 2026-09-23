# Automated Mac releases

Open **Actions → Mac release → Run workflow**, choose `main`, enter a version (such as `0.12.1`) and a new build number (greater than 32). Leave Publish off for build/test validation. Turn Publish on to ship. No one needs to sign in to Apple interactively on each release.

## One-time setup

Add these under repository **Settings → Secrets and variables → Actions → New repository secret**. Never paste credentials in chat, commits, issues, or workflow logs.

Ebuka supplies:

| Secret | Value |
|---|---|
| `WAND_CERTIFICATE_BASE64` | Base64 of a password-protected .p12 export containing the **Developer ID Application certificate AND its private key** used for build 32. Do not use Apple Development or Developer ID Installer. |
| `WAND_CERTIFICATE_PASSWORD` | Password for that export. |
| `WAND_NOTARY_KEY_BASE64` | Base64 of the .p8 private key for an App Store Connect **team API key** authorized for notarization. |
| `WAND_NOTARY_KEY_ID` | API key ID. |
| `WAND_NOTARY_ISSUER_ID` | Team API issuer ID. |

Thabhelo supplies:

| Secret | Value |
|---|---|
| `GH_RELEASE_TOKEN` | Fine-grained token owned by **Thabhelo**, restricted to Thabhelo/wand, with Contents read/write. It records the new signed release files and download page on main. The workflow verifies the effective GitHub actor immediately before pushing. |
| `CLOUDFLARE_API_TOKEN` | Token restricted to Wand's Cloudflare account: Workers Scripts Edit; the zone permissions needed for the existing custom domains (Zone Read and Workers Routes Edit). Account ID is public configuration in the workflow. |

The GitHub repository admin may need to enter secrets if contributor permissions do not expose Settings. Use secure credential transfer if necessary; do not increase repository access merely to collect secrets. Sharing a signing private key delegates the ability to sign software as its owner: Ebuka must explicitly agree. Do not export his key without his authorization. No Apple account password is required.

Signing team is pinned to `AX35NK3J3A`, the notarized build 32 identity. Certificate renewal within the same team is supported; switching teams is a migration requiring a reviewed code change. Stable identity reduces permission churn but cannot guarantee macOS never asks again.

## Release behavior

- Runs only from main on an ephemeral macOS 26 ARM runner; third-party Actions are pinned by commit.
- Checks version/build monotonicity, Swift tests, release compilation and website tests before using secrets.
- Imports the signing key into a temporary Keychain, enables codesign access there only, and removes the Keychain and key files even after failure.
- Signs with hardened runtime, obtains Apple's acceptance, staples the app, builds an installer with an Applications link, notarizes/staples the installer, and verifies signatures and checksums.
- Uploads the resulting DMG/checksum as a short-lived Actions artifact for recovery.
- Stops if main changed during the build. Otherwise commits the release to main, deploys with the Cloudflare API token, then checks the public page and exact download hash.
- If deployment fails AFTER the release commit, source is ahead of the website. Deploy the committed site from main; don't rebuild or overwrite that build number. An Actions failure is never a successful publication.

Before announcing a feature, still run its live device tests. CI does not test a real user's Accessibility, Screen Recording, Keychain migration, or Muse integration.

## Password prompts

Notarization proves Apple's malware assessment and signing trust; it does not grant Keychain or desktop permissions. Moving from Thabhelo's development team to Ebuka's Developer ID team changes the app identity. Legacy credentials or one-time Allow decisions may produce more than one prompt. Six prompts are not the expected normal update experience. For a recognized Wand Keychain prompt, Always Allow remembers access for that item. Do not reset macOS permissions, disable Keychain protection, or store tokens in plaintext to suppress prompts. Verify restart/update persistence separately before calling the migration fixed.

References: https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications and https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
